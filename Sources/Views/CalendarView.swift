import SwiftUI

/// Look-ahead planning: a week strip or month grid, with the selected day's
/// timeline underneath. The selected day decides which week or month is showing.
struct CalendarView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"
        var id: String { rawValue }
    }

    @Environment(EventKitService.self) private var eventKit
    @Binding var selectedDay: Date
    @AppStorage("calendarMode") private var mode = Mode.week
    @State private var items: [TimelineItem] = []
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
            .navigationBarTitleDisplayMode(.inline)
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

            Section(dayTitle) {
                if items.isEmpty {
                    if hasLoaded {
                        Text("Nothing scheduled. Tap + to add something.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(items) { item in
                        TimelineRow(item: item) {
                            Task { await loadDay() }
                        }
                    }
                }
            }
        }
        .contentMargins(.bottom, ComposerButtonClearance.height, for: .scrollContent)
        .refreshable {
            await loadDay()
            await loadMarks()
        }
        .task(id: [selectedDay.timeIntervalSince1970, Double(eventKit.changeCount)]) {
            await loadDay()
        }
        .task(id: [
            visibleDays.first?.timeIntervalSince1970 ?? 0,
            Double(visibleDays.count),
            Double(eventKit.changeCount),
        ]) {
            await loadMarks()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Today") {
                selectedDay = calendar.startOfDay(for: .now)
            }
            .disabled(calendar.isDateInToday(selectedDay))
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                shiftPeriod(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous \(mode.rawValue.lowercased())")
        }
        ToolbarItem(placement: .topBarTrailing) {
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
        if calendar.isDateInToday(selectedDay) { return "Today" }
        if calendar.isDateInTomorrow(selectedDay) { return "Tomorrow" }
        return selectedDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
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
                    .foregroundStyle(.secondary)
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
                            Circle().fill(.tint)
                        }
                    }
                    .foregroundStyle(dayColor(isSelected: isSelected, isToday: isToday, isDimmed: isDimmed))

                Circle()
                    .fill(.secondary)
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

    private func dayColor(isSelected: Bool, isToday: Bool, isDimmed: Bool) -> AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.white) }
        if isToday { return AnyShapeStyle(.tint) }
        return AnyShapeStyle(isDimmed ? .tertiary : .primary)
    }
}
