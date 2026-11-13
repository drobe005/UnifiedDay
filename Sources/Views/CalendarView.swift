import SwiftUI

/// Look-ahead planning: a week strip or month grid, with the selected day's
/// timeline underneath. The selected day decides which week or month is showing.
struct CalendarView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"
        var id: String { rawValue }
    }

    /// What the list under the grid covers.
    enum Scope: String, CaseIterable, Identifiable {
        case day, period, custom
        var id: String { rawValue }
    }

    enum Kind: String, CaseIterable, Identifiable {
        case all = "Events and Reminders"
        case events = "Events"
        case reminders = "Reminders"
        var id: String { rawValue }

        func includes(_ item: TimelineItem) -> Bool {
            switch self {
            case .all: true
            case .events: item.kind == .event
            case .reminders: item.kind == .reminder
            }
        }
    }

    @Environment(EventKitService.self) private var eventKit
    @Binding var selectedDay: Date
    @AppStorage("calendarMode") private var mode = Mode.week
    @AppStorage("calendarScope") private var scope = Scope.day
    @AppStorage("calendarKind") private var kind = Kind.all
    @State private var items: [TimelineItem] = []
    @State private var rangeItems: [TimelineItem] = []
    @State private var customStart = Calendar.current.startOfDay(for: .now)
    @State private var customEnd = Calendar.current.date(byAdding: .day, value: 6, to: Calendar.current.startOfDay(for: .now)) ?? .now
    @State private var markedDays = Set<Date>()
    @State private var hasLoaded = false

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            Group {
                if eventKit.accessGranted {
                    content
                } else {
                    AccessPromptView { Task { _ = await eventKit.requestAccess() } }
                }
            }
            .navigationTitle(selectedDay.formatted(.dateTime.month(.wide).year()))
            .udInlineTitle()
            .toolbar { toolbar }
        }
    }

    // MARK: - Layout

    private var content: some View {
        List {
            Section {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                CalendarGrid(
                    days: visibleDays,
                    month: mode == .month ? selectedDay : nil,
                    selectedDay: $selectedDay,
                    markedDays: markedDays
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                .simultaneousGesture(swipeToChangePeriod)
            }
            .listRowSeparator(.hidden)

            Section {
                filters
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: UD.screenPadding, bottom: 4, trailing: UD.screenPadding))
                if scope == .custom {
                    UDCard {
                        DatePicker("From", selection: $customStart, displayedComponents: .date)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        UDDivider()
                        DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(UD.textPrimary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: UD.screenPadding, bottom: 4, trailing: UD.screenPadding))
                }
            }
            .listRowSeparator(.hidden)

            if scope == .day {
                daySection
            } else {
                rangeSections
            }
        }
        .listStyle(.plain)
        .udListSectionSpacing(0)
        .udScreenBackground()
        .contentMargins(.bottom, ComposerButtonClearance.height, for: .scrollContent)
        .refreshable {
            await reload()
            await loadMarks()
        }
        .task(id: [selectedDay.timeIntervalSince1970, Double(eventKit.changeCount)]) {
            await loadDay()
        }
        .task(id: rangeKey) {
            await loadRange()
        }
        .task(id: [
            visibleDays.first?.timeIntervalSince1970 ?? 0,
            Double(visibleDays.count),
            Double(eventKit.changeCount),
        ]) {
            await loadMarks()
        }
    }

    /// What the list shows and which kinds of items, as two compact menu buttons.
    private var filters: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Show", selection: $scope) {
                    Text("Selected day").tag(Scope.day)
                    Text(mode == .week ? "All this week" : "All this month").tag(Scope.period)
                    Text("Custom range").tag(Scope.custom)
                }
            } label: {
                FilterChip(icon: "calendar", text: scopeLabel)
            }
            .accessibilityLabel("Show, \(scopeLabel)")

            Menu {
                Picker("Include", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                FilterChip(icon: "line.3.horizontal.decrease", text: kindLabel)
            }
            .accessibilityLabel("Include, \(kind.rawValue)")

            Spacer(minLength: 0)
        }
    }

    private var scopeLabel: String {
        switch scope {
        case .day: "Selected day"
        case .period: mode == .week ? "This week" : "This month"
        case .custom: "Custom range"
        }
    }

    private var kindLabel: String {
        switch kind {
        case .all: "All items"
        case .events: "Events"
        case .reminders: "Reminders"
        }
    }

    private func emptyRow(_ text: String) -> some View {
        UDEmptyListRow(text: text)
    }

    private var daySection: some View {
        let visible = items.filter(kind.includes)
        return Section {
            if visible.isEmpty {
                if hasLoaded {
                    emptyRow("Nothing scheduled. Tap + to add something.")
                }
            } else {
                ForEach(visible) { item in
                    TimelineRow(item: item) {
                        Task { await loadDay() }
                    } onRemove: { removed, target in
                        if let target, calendar.isDate(target.day(), inSameDayAs: selectedDay) { return }
                        items.removeAll { $0.id == removed.id }
                    }
                }
            }
        } header: {
            UDListHeader(title: dayTitle, count: hasLoaded ? visible.count : nil)
        }
    }

    @ViewBuilder
    private var rangeSections: some View {
        let days = rangeDays
        if days.isEmpty {
            Section {
                emptyRow("Nothing scheduled in this range.")
            } header: {
                UDListHeader(title: rangeTitle)
            }
        }
        ForEach(days, id: \.day) { group in
            Section {
                ForEach(group.items) { item in
                    TimelineRow(item: item) {
                        Task { await loadRange() }
                    } onRemove: { removed, target in
                        if let target, let range, range.contains(target.day()) { return }
                        rangeItems.removeAll { $0.id == removed.id }
                    }
                }
            } header: {
                UDListHeader(title: title(for: group.day), count: group.items.count)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .udLeading) {
            Button("Today") {
                selectedDay = calendar.startOfDay(for: .now)
            }
            .disabled(calendar.isDateInToday(selectedDay))
        }
        ToolbarItem(placement: .udTrailing) {
            Button {
                shiftPeriod(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous \(mode.rawValue.lowercased())")
        }
        ToolbarItem(placement: .udTrailing) {
            Button {
                shiftPeriod(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next \(mode.rawValue.lowercased())")
        }
    }

    private var swipeToChangePeriod: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { value in
            let width = value.translation.width
            guard abs(width) > abs(value.translation.height), abs(width) > 50 else { return }
            shiftPeriod(by: width < 0 ? 1 : -1)
        }
    }

    // MARK: - Dates

    private var dayTitle: String {
        title(for: selectedDay)
    }

    private func title(for day: Date) -> String {
        Self.title(for: day)
    }

    /// "Today", "Tomorrow", or the weekday and date.
    static func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// The days the list covers when showing more than one day. Nil for one day.
    private var range: Range<Date>? {
        Self.range(scope: scope, mode: mode, selectedDay: selectedDay, customStart: customStart, customEnd: customEnd)
    }

    static func range(scope: Scope, mode: Mode, selectedDay: Date, customStart: Date, customEnd: Date) -> Range<Date>? {
        let calendar = Calendar.current
        switch scope {
        case .day:
            return nil
        case .period:
            guard let interval = calendar.dateInterval(of: mode == .week ? .weekOfYear : .month, for: selectedDay) else {
                return nil
            }
            return interval.start..<interval.end
        case .custom:
            let start = calendar.startOfDay(for: customStart)
            // Capped at a year so a stray date can't load years of items.
            let lastDay = min(max(customEnd, start), calendar.date(byAdding: .year, value: 1, to: start) ?? start)
            guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDay)) else {
                return nil
            }
            return start..<end
        }
    }

    private var rangeTitle: String {
        guard let range else { return dayTitle }
        return Self.title(for: range)
    }

    /// "Nov 3 to Nov 9".
    static func title(for range: Range<Date>) -> String {
        let last = range.upperBound.addingTimeInterval(-1)
        return "\(range.lowerBound.formatted(.dateTime.month(.abbreviated).day())) to \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var rangeKey: [Double] {
        guard let range else { return [0] }
        return [range.lowerBound.timeIntervalSince1970, range.upperBound.timeIntervalSince1970, Double(eventKit.changeCount)]
    }

    /// Items grouped by day. Multi-day events show on each day they cover.
    private var rangeDays: [(day: Date, items: [TimelineItem])] {
        guard let range else { return [] }
        return Self.groupByDay(rangeItems.filter(kind.includes), in: range)
    }

    static func groupByDay(_ items: [TimelineItem], in range: Range<Date>) -> [(day: Date, items: [TimelineItem])] {
        let calendar = Calendar.current
        var byDay: [Date: [TimelineItem]] = [:]
        for item in items {
            guard let start = item.startDate else { continue }
            let last = max(start, (item.endDate ?? start).addingTimeInterval(item.endDate == nil ? 0 : -1))
            var day = calendar.startOfDay(for: max(start, range.lowerBound))
            while day <= last, day < range.upperBound {
                byDay[day, default: []].append(item)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return byDay.keys.sorted().map { (day: $0, items: EventKitService.sortItems(byDay[$0] ?? [])) }
    }

    /// Whole weeks: seven days in week mode, every week the month touches in month mode.
    private var visibleDays: [Date] {
        Self.visibleDays(mode: mode, selectedDay: selectedDay)
    }

    static func visibleDays(mode: Mode, selectedDay: Date) -> [Date] {
        let calendar = Calendar.current
        let start: Date?
        let end: Date?
        if mode == .week {
            let week = calendar.dateInterval(of: .weekOfYear, for: selectedDay)
            start = week?.start
            end = week?.end
        } else {
            let month = calendar.dateInterval(of: .month, for: selectedDay)
            start = month.flatMap { calendar.dateInterval(of: .weekOfYear, for: $0.start)?.start }
            end = month.flatMap { calendar.dateInterval(of: .weekOfYear, for: $0.end.addingTimeInterval(-1))?.end }
        }
        guard let start, let end else { return [] }

        var days: [Date] = []
        var day = start
        while day < end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    private func shiftPeriod(by amount: Int) {
        selectedDay = Self.shifted(selectedDay, mode: mode, by: amount)
    }

    /// The day selected after moving a week or month forward or back.
    static func shifted(_ selectedDay: Date, mode: Mode, by amount: Int) -> Date {
        let calendar = Calendar.current
        let unit: Calendar.Component = mode == .week ? .weekOfYear : .month
        guard let day = calendar.date(byAdding: unit, value: amount, to: selectedDay) else { return selectedDay }
        if mode == .week {
            return calendar.startOfDay(for: day)
        } else if calendar.isDate(day, equalTo: .now, toGranularity: .month) {
            return calendar.startOfDay(for: .now)
        } else {
            // A new month opens on its 1st, not on whatever date it shifted to.
            return calendar.dateInterval(of: .month, for: day)?.start ?? day
        }
    }

    // MARK: - Loading

    private func reload() async {
        if scope == .day {
            await loadDay()
        } else {
            await loadRange()
        }
    }

    private func loadRange() async {
        guard let range else { return }
        let loaded = await eventKit.fetchRange(from: range.lowerBound, to: range.upperBound)
        guard range == self.range else { return }
        rangeItems = loaded
    }

    private func loadDay() async {
        let day = selectedDay
        let loaded = await eventKit.fetchTimeline(for: day)
        guard day == selectedDay else { return }
        items = loaded
        hasLoaded = true
    }

    private func loadMarks() async {
        guard let first = visibleDays.first,
              let last = visibleDays.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return }
        let marks = await eventKit.daysWithItems(from: first, to: end)
        guard !Task.isCancelled else { return }
        markedDays = marks
    }
}

/// Seven-column day grid, shared by the week strip and the month view.
struct CalendarGrid: View {
    let days: [Date]
    /// The month being shown. Days outside it are dimmed. Nil in week mode.
    let month: Date?
    @Binding var selectedDay: Date
    let markedDays: Set<Date>

    private var calendar: Calendar { .current }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(UD.textTertiary)
                    .accessibilityHidden(true)
            }
            ForEach(days, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        let isDimmed = month.map { !calendar.isDate(day, equalTo: $0, toGranularity: .month) } ?? false
        let isMarked = markedDays.contains(day)

        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.day()))
                    .font(.body.monospacedDigit().weight(isToday || isSelected ? .bold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: 34, height: 34)
                    .background {
                        if isSelected {
                            Circle().fill(UD.brand600)
                        } else if isToday {
                            Circle().fill(UD.brand50)
                        }
                    }
                    .foregroundStyle(dayColor(isSelected: isSelected, isToday: isToday, isDimmed: isDimmed))

                Circle()
                    .fill(UD.brand500)
                    .frame(width: 5, height: 5)
                    .opacity(isMarked ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(isMarked ? "Has items" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func dayColor(isSelected: Bool, isToday: Bool, isDimmed: Bool) -> Color {
        if isSelected { return .white }
        if isToday { return UD.brand700 }
        return isDimmed ? UD.textQuaternary : UD.textPrimary
    }
}
