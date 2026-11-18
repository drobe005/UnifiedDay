import SwiftUI

/// Look-ahead planning: a week strip or month grid, with the selected day's
/// events underneath. The selected day decides which week or month is showing.
/// Events only: reminders live in the Reminders tab, and Today shows both.
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

    @Environment(EventKitService.self) private var eventKit
    @Binding var selectedDay: Date
    @AppStorage("calendarMode") private var mode = Mode.week
    @AppStorage("calendarScope") private var scope = Scope.day
    @State private var items: [TimelineItem] = []
    @State private var rangeItems: [TimelineItem] = []
    @State private var customStart = Calendar.current.startOfDay(for: .now)
    @State private var customEnd = Calendar.current.date(byAdding: .day, value: 6, to: Calendar.current.startOfDay(for: .now)) ?? .now
    @State private var markedDays: [Date: EventKitService.DayMarks] = [:]
    @State private var hasLoaded = false
    /// Days whose list is folded shut. Not saved, so every visit starts open.
    @State private var collapsedDays: Set<Date> = []

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
            .navigationTitle(selectedDay.formatted(.dateTime.month(.wide)))
            .toolbar { toolbar }
        }
    }

    // MARK: - Layout

    private var content: some View {
        List {
            Section {
                // Week and Month on the left, what the list covers on the right.
                HStack(spacing: 12) {
                    UDTextTabs(options: Mode.allCases.map { ($0, $0.rawValue) }, selection: $mode)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("View")
                    scopeMenu
                }
                .udPlainRow()

                CalendarGrid(
                    days: visibleDays,
                    month: mode == .month ? selectedDay : nil,
                    selectedDay: $selectedDay,
                    markedDays: markedDays
                )
                .padding(.top, 4)
                .udPlainRow()
                .simultaneousGesture(swipeToChangePeriod)

                if scope == .custom {
                    Group {
                        DatePicker("From", selection: $customStart, displayedComponents: .date)
                        DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
                    }
                    .foregroundStyle(UD.textSecondary)
                    .tint(UD.brand600)
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) { UDDivider() }
                    .udPlainRow()
                }
            }

            if scope == .day {
                daySection
            } else {
                rangeSections
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
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

    /// Which days the list covers, as a small gray menu.
    private var scopeMenu: some View {
        Menu {
            Picker("Show", selection: $scope) {
                Text("Selected day").tag(Scope.day)
                Text(mode == .week ? "All this week" : "All this month").tag(Scope.period)
                Text("Custom range").tag(Scope.custom)
            }
        } label: {
            FilterChip(text: scopeLabel)
        }
        .accessibilityLabel("Show, \(scopeLabel)")
    }

    private var scopeLabel: String {
        switch scope {
        case .day: "Selected day"
        case .period: mode == .week ? "This week" : "This month"
        case .custom: "Custom range"
        }
    }

    private func emptyRow(_ text: String) -> some View {
        UDEmptyListRow(text: text)
    }

    private var daySection: some View {
        let visible = items.filter { $0.kind == .event }
        let collapsed = isCollapsed(selectedDay)
        return Section {
            if collapsed {
                EmptyView()
            } else if visible.isEmpty {
                if hasLoaded {
                    emptyRow("No events. Tap + to add one.")
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
            UDFoldableHeader(
                title: dayTitle,
                count: hasLoaded ? visible.count : nil,
                isCollapsed: collapsed,
                showHint: "Shows this day's events",
                hideHint: "Hides this day's events"
            ) {
                toggle(selectedDay)
            }
        }
    }

    @ViewBuilder
    private var rangeSections: some View {
        let days = rangeDays
        if days.isEmpty {
            Section {
                emptyRow("No events in this range.")
            } header: {
                UDListHeader(title: rangeTitle)
            }
        }
        ForEach(days, id: \.day) { group in
            Section {
                if !isCollapsed(group.day) {
                    ForEach(group.items) { item in
                        TimelineRow(item: item) {
                            Task { await loadRange() }
                        } onRemove: { removed, target in
                            if let target, let range, range.contains(target.day()) { return }
                            rangeItems.removeAll { $0.id == removed.id }
                        }
                    }
                }
            } header: {
                UDFoldableHeader(
                    title: title(for: group.day),
                    count: group.items.count,
                    isCollapsed: isCollapsed(group.day),
                    showHint: "Shows this day's events",
                    hideHint: "Hides this day's events"
                ) {
                    toggle(group.day)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        UDOverlineToolbarItem(text: selectedDay.formatted(.dateTime.year()))
        ToolbarItem(placement: .topBarTrailing) {
            Button("Today") {
                selectedDay = calendar.startOfDay(for: .now)
            }
            .fontWeight(.semibold)
            .disabled(calendar.isDateInToday(selectedDay))
            // Swipe the week or month to move; the arrows are gone, as in Figma.
            .accessibilityHint("Swipe the calendar left or right to change the \(mode.rawValue.lowercased())")
        }
        .udPlain()
    }

    private var swipeToChangePeriod: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { value in
            let width = value.translation.width
            guard abs(width) > abs(value.translation.height), abs(width) > 50 else { return }
            shiftPeriod(by: width < 0 ? 1 : -1)
        }
    }

    // MARK: - Folding

    private func isCollapsed(_ day: Date) -> Bool {
        collapsedDays.contains(calendar.startOfDay(for: day))
    }

    private func toggle(_ day: Date) {
        let key = calendar.startOfDay(for: day)
        if collapsedDays.contains(key) { collapsedDays.remove(key) } else { collapsedDays.insert(key) }
    }

    // MARK: - Dates

    private var dayTitle: String {
        title(for: selectedDay)
    }

    private func title(for day: Date) -> String {
        // Always the date, as in Figma, so the list matches the day picked above it.
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// The days the list covers when showing more than one day. Nil for one day.
    private var range: Range<Date>? {
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
        var byDay: [Date: [TimelineItem]] = [:]
        for item in rangeItems where item.kind == .event {
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
        let unit: Calendar.Component = mode == .week ? .weekOfYear : .month
        guard let day = calendar.date(byAdding: unit, value: amount, to: selectedDay) else { return }
        if mode == .week {
            selectedDay = calendar.startOfDay(for: day)
        } else if calendar.isDate(day, equalTo: .now, toGranularity: .month) {
            selectedDay = calendar.startOfDay(for: .now)
        } else {
            // A new month opens on its 1st, not on whatever date it shifted to.
            selectedDay = calendar.dateInterval(of: .month, for: day)?.start ?? day
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
        // Dots mark events only, so a day gets one only when its list would show something.
        let marks = await eventKit.dayMarks(from: first, to: end, events: true, reminders: false)
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
    let markedDays: [Date: EventKitService.DayMarks]

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
                    .font(.caption.weight(.medium))
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
        let marks = markedDays[day]
        let isMarked = marks != nil

        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.day()))
                    .font(.body.monospacedDigit().weight(isToday || isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: 34, height: 34)
                    .background {
                        // Brand blue marks the selected day only. Today is bold brand text.
                        if isSelected {
                            Circle().fill(UD.brand600)
                        }
                    }
                    .foregroundStyle(dayColor(isSelected: isSelected, isToday: isToday, isDimmed: isDimmed))

                DayDots(marks: marks)
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

/// Up to three dots under a day: one per calendar with events that day, in that
/// calendar's color, then one in the reminder color when a reminder is due.
/// Keeps its height when empty so every row of days lines up.
struct DayDots: View {
    let marks: EventKitService.DayMarks?

    private static let maxDots = 3

    private var colors: [Color] {
        guard let marks else { return [] }
        let eventSlots = marks.hasReminder ? Self.maxDots - 1 : Self.maxDots
        var colors = Array(marks.eventColors.prefix(eventSlots))
        if marks.hasReminder { colors.append(UD.warningFg) }
        return colors
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}
