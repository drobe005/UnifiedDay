#if os(macOS)
import SwiftUI

/// Calendar on the Mac: a large week or month grid with each day's items written
/// in, and the selected day (or range) listed on the right.
struct MacCalendarView: View {
    typealias Mode = CalendarView.Mode
    typealias Scope = CalendarView.Scope
    typealias Kind = CalendarView.Kind

    @Environment(EventKitService.self) private var eventKit
    @Binding var selectedDay: Date
    // Same settings as the iPhone screen, so both remember the same view.
    @AppStorage("calendarMode") private var mode = Mode.week
    @AppStorage("calendarScope") private var scope = Scope.day
    @AppStorage("calendarKind") private var kind = Kind.all
    @State private var gridItems: [TimelineItem] = []
    @State private var dayItems: [TimelineItem] = []
    @State private var rangeItems: [TimelineItem] = []
    @State private var customStart = Calendar.current.startOfDay(for: .now)
    @State private var customEnd = Calendar.current.date(byAdding: .day, value: 6, to: Calendar.current.startOfDay(for: .now)) ?? .now
    @State private var hasLoadedDay = false
    @State private var openingItem: TimelineItem?

    private var calendar: Calendar { .current }

    private var visibleDays: [Date] {
        CalendarView.visibleDays(mode: mode, selectedDay: selectedDay)
    }

    private var range: Range<Date>? {
        CalendarView.range(scope: scope, mode: mode, selectedDay: selectedDay, customStart: customStart, customEnd: customEnd)
    }

    /// Grid items by day. Multi-day events show on each day they cover.
    private var itemsByDay: [Date: [TimelineItem]] {
        guard let first = visibleDays.first, let last = visibleDays.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return [:] }
        let groups = CalendarView.groupByDay(gridItems.filter(kind.includes), in: first..<end)
        return Dictionary(uniqueKeysWithValues: groups.map { ($0.day, $0.items) })
    }

    var body: some View {
        VStack(spacing: 0) {
            MacScreenHeader(title: selectedDay.formatted(.dateTime.month(.wide).year())) {
                Button("Today") {
                    selectedDay = calendar.startOfDay(for: .now)
                }
                .buttonStyle(UDSmallButtonStyle())
                .disabled(calendar.isDateInToday(selectedDay))
                MacIconButton(help: "Previous \(mode.rawValue.lowercased())") {
                    selectedDay = CalendarView.shifted(selectedDay, mode: mode, by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                MacIconButton(help: "Next \(mode.rawValue.lowercased())") {
                    selectedDay = CalendarView.shifted(selectedDay, mode: mode, by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                MacNewButton()
            }

            if eventKit.accessGranted {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 12) {
                        filters
                        grid
                    }
                    .padding(.horizontal, MacLayout.contentPadding)
                    .padding(.bottom, MacLayout.contentPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    dayList
                        .frame(width: 320)
                        .frame(maxHeight: .infinity)
                        .background(UD.bgCard)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(UD.borderSecondary).frame(width: 1)
                        }
                }
            } else {
                AccessPromptView { Task { _ = await eventKit.requestAccess() } }
            }
        }
        .sheet(item: $openingItem) { item in
            ItemDetailView(item: item) {}
                .environment(eventKit)
        }
        .task(id: [
            visibleDays.first?.timeIntervalSince1970 ?? 0,
            Double(visibleDays.count),
            Double(eventKit.changeCount),
        ]) {
            await loadGrid()
        }
        .task(id: [selectedDay.timeIntervalSince1970, Double(eventKit.changeCount)]) {
            await loadDay()
        }
        .task(id: rangeKey) {
            await loadRange()
        }
    }

    // MARK: - Filters

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
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()

            Menu {
                Picker("Include", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                FilterChip(icon: "line.3.horizontal.decrease", text: kindLabel)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()

            if scope == .custom {
                DatePicker("From", selection: $customStart, displayedComponents: .date)
                    .fixedSize()
                DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
                    .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .foregroundStyle(UD.textSecondary)
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

    // MARK: - Grid

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var weeks: [[Date]] {
        stride(from: 0, to: visibleDays.count, by: 7).map { Array(visibleDays[$0..<min($0 + 7, visibleDays.count)]) }
    }

    private var grid: some View {
        let byDay = itemsByDay
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(UD.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .background(UD.bgSubtle)
            ForEach(weeks, id: \.first) { week in
                UDDivider()
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.element) { index, day in
                        if index > 0 {
                            Rectangle().fill(UD.borderSecondary).frame(width: 1)
                        }
                        dayCell(day, items: byDay[day] ?? [])
                    }
                }
            }
        }
        .background(UD.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: UD.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: UD.cardRadius, style: .continuous)
                .strokeBorder(UD.borderSecondary)
        )
        .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
    }

    private func dayCell(_ day: Date, items: [TimelineItem]) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        let inMonth = mode == .week || calendar.isDate(day, equalTo: selectedDay, toGranularity: .month)
        let limit = mode == .week ? 12 : 3
        return VStack(alignment: .leading, spacing: 3) {
            Text(day.formatted(.dateTime.day()))
                .font(.subheadline.monospacedDigit().weight(isToday || isSelected ? .bold : .medium))
                .foregroundStyle(isToday ? .white : inMonth ? UD.textPrimary : UD.textQuaternary)
                .frame(minWidth: 24, minHeight: 24)
                .background {
                    if isToday { Circle().fill(UD.brand600) }
                }
            ForEach(items.prefix(limit)) { item in
                chip(item)
            }
            if items.count > limit {
                Text("+\(items.count - limit) more")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(UD.textTertiary)
                    .padding(.leading, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isSelected ? UD.brand50 : .clear)
        .overlay {
            if isSelected {
                Rectangle().strokeBorder(UD.brand500, lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedDay = day }
        .accessibilityAction { selectedDay = day }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(items.isEmpty ? "" : "\(items.count) items")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// One item in a day cell: a calendar-colored square for events, an open circle
    /// for reminders.
    private func chip(_ item: TimelineItem) -> some View {
        Button {
            openingItem = item
        } label: {
            HStack(spacing: 5) {
                if item.kind == .event {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(item.sourceColor)
                        .frame(width: 8, height: 8)
                } else {
                    Circle()
                        .strokeBorder(item.isOverdue ? UD.errorFg : UD.textTertiary, lineWidth: 1.2)
                        .frame(width: 9, height: 9)
                }
                Text(item.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(item.isCompleted ? UD.textTertiary : UD.textStrong)
                    .strikethrough(item.isCompleted)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                item.kind == .event ? item.sourceColor.opacity(0.12) : .clear,
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.title)
    }

    // MARK: - Day list

    @ViewBuilder
    private var dayList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if let range {
                    let days = CalendarView.groupByDay(rangeItems.filter(kind.includes), in: range)
                    if days.isEmpty {
                        UDListHeader(title: CalendarView.title(for: range))
                        UDEmptyListRow(text: "Nothing scheduled in this range.")
                    }
                    ForEach(days, id: \.day) { group in
                        UDListHeader(title: CalendarView.title(for: group.day), count: group.items.count)
                        ForEach(group.items) { item in
                            TimelineRow(item: item) { Task { await loadRange() } }
                        }
                    }
                } else {
                    let visible = dayItems.filter(kind.includes)
                    UDListHeader(title: CalendarView.title(for: selectedDay), count: hasLoadedDay ? visible.count : nil)
                    if visible.isEmpty && hasLoadedDay {
                        UDEmptyListRow(text: "Nothing scheduled. Press Cmd N to add something.")
                    }
                    ForEach(visible) { item in
                        TimelineRow(item: item) { Task { await loadDay() } }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Loading

    private var rangeKey: [Double] {
        guard let range else { return [0] }
        return [range.lowerBound.timeIntervalSince1970, range.upperBound.timeIntervalSince1970, Double(eventKit.changeCount)]
    }

    private func loadGrid() async {
        guard eventKit.accessGranted, let first = visibleDays.first, let last = visibleDays.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return }
        let loaded = await eventKit.fetchRange(from: first, to: end)
        guard !Task.isCancelled else { return }
        gridItems = loaded
    }

    private func loadDay() async {
        guard eventKit.accessGranted else { return }
        let day = selectedDay
        let loaded = await eventKit.fetchTimeline(for: day)
        guard day == selectedDay else { return }
        dayItems = loaded
        hasLoadedDay = true
    }

    private func loadRange() async {
        guard eventKit.accessGranted, let range else { return }
        let loaded = await eventKit.fetchRange(from: range.lowerBound, to: range.upperBound)
        guard range == self.range else { return }
        rangeItems = loaded
    }
}
#endif
