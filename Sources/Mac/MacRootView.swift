#if os(macOS)
import SwiftData
import SwiftUI

/// The Mac window from the Figma "Mac app" page: a sidebar with search, the
/// screens and a small month, and the selected screen beside it.
struct MacRootView: View {
    @Binding var selectedTab: AppTab
    @Binding var calendarDay: Date
    let tabs: [AppTab]

    @State private var searchText = ""
    /// The note open in the Notes screen. Kept here so search results can open one.
    @State private var selectedNoteID: PersistentIdentifier?

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 0) {
            MacSidebar(
                selectedTab: $selectedTab,
                calendarDay: $calendarDay,
                searchText: $searchText,
                tabs: tabs
            )
            ZStack {
                if trimmedSearch.isEmpty {
                    screen
                } else {
                    MacSearchView(query: trimmedSearch) { note in
                        selectedNoteID = note.persistentModelID
                        searchText = ""
                        selectedTab = .notes
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(UD.bgScreen)
        }
        // The window has no title bar, so the sidebar runs to the top edge and the
        // window buttons sit over it.
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: selectedTab) {
            searchText = ""
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch selectedTab {
        case .today: MacTodayView()
        case .calendar: MacCalendarView(selectedDay: $calendarDay)
        case .reminders: MacRemindersView()
        case .notes: MacNotesView(selectedNoteID: $selectedNoteID)
        case .settings:
            SettingsView()
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .padding(.top, MacLayout.titleBarHeight)
        }
    }
}

/// Sizes shared by the Mac screens.
enum MacLayout {
    /// Room for the window buttons, since the window has no title bar.
    static let titleBarHeight: CGFloat = 28
    static let sidebarWidth: CGFloat = 260
    static let detailPanelWidth: CGFloat = 360
    static let contentPadding: CGFloat = 24
}

// MARK: - Screen header

/// Title row at the top of each Mac screen: an optional small line above the title,
/// then buttons on the right.
struct MacScreenHeader<Trailing: View>: View {
    var caption: String?
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let caption {
                    Text(caption)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(UD.brand700)
                }
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(UD.textPrimary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            HStack(spacing: 8) { trailing }
        }
        .padding(.horizontal, MacLayout.contentPadding)
        .padding(.top, MacLayout.titleBarHeight + 16)
        .padding(.bottom, 16)
    }
}

/// Square outlined icon button for screen headers.
struct MacIconButton<Label: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            label
                .frame(width: 18, height: 18)
        }
        .buttonStyle(UDSmallButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The New button in screen headers. Same as File > New Item (Cmd N).
struct MacNewButton: View {
    @Environment(\.appActions) private var actions

    var body: some View {
        Button {
            actions?.newItem()
        } label: {
            Label("New", systemImage: "plus")
        }
        .buttonStyle(UDSmallButtonStyle(prominent: true))
        .fixedSize()
        .disabled(actions?.canAdd != true)
        .help("New event, reminder, or note (Cmd N)")
    }
}

// MARK: - Sidebar

private struct MacSidebar: View {
    @Environment(EventKitService.self) private var eventKit
    @Binding var selectedTab: AppTab
    @Binding var calendarDay: Date
    @Binding var searchText: String
    let tabs: [AppTab]

    @State private var attentionCount = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            searchField
            VStack(spacing: 2) {
                ForEach(tabs) { tab in
                    row(for: tab)
                }
            }
            if eventKit.accessGranted {
                MiniMonth(selectedDay: calendarDay) { day in
                    calendarDay = day
                    selectedTab = .calendar
                }
            }
            Spacer(minLength: 0)
            row(for: .settings)
        }
        .padding(.horizontal, 16)
        .padding(.top, MacLayout.titleBarHeight + 24)
        .padding(.bottom, 16)
        .frame(width: MacLayout.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(UD.bgSubtle)
        .overlay(alignment: .trailing) {
            Rectangle().fill(UD.borderSecondary).frame(width: 1)
        }
        .task(id: eventKit.changeCount) {
            guard eventKit.accessGranted else { return }
            attentionCount = await eventKit.fetchNeedsAttention().count
        }
        .onChange(of: eventKit.accessGranted) {
            Task { attentionCount = await eventKit.fetchNeedsAttention().count }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(UD.textTertiary)
            TextField("Search items and notes", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onExitCommand { searchText = "" }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(UD.textQuaternary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(.body)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(UD.bgCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(searchFocused ? UD.brand500 : UD.borderPrimary)
        )
        .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
    }

    private func row(for tab: AppTab) -> some View {
        let isActive = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.systemImage)
                    .frame(width: 20)
                    .foregroundStyle(isActive ? UD.brand600 : UD.textTertiary)
                Text(tab.title)
                    .font(.body.weight(isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? UD.brand700 : UD.textStrong)
                Spacer(minLength: 0)
                if tab == .reminders && attentionCount > 0 {
                    UDBadge(text: "\(attentionCount)", tone: isActive ? .brand : .gray)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isActive ? UD.brand100 : .clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Mini month

/// A small month in the sidebar. Dots mark days with items; a click opens that day
/// in Calendar.
private struct MiniMonth: View {
    @Environment(EventKitService.self) private var eventKit
    let selectedDay: Date
    let onSelect: (Date) -> Void

    @State private var month: Date
    @State private var markedDays = Set<Date>()

    init(selectedDay: Date, onSelect: @escaping (Date) -> Void) {
        self.selectedDay = selectedDay
        self.onSelect = onSelect
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: selectedDay)?.start ?? selectedDay)
    }

    private var calendar: Calendar { .current }

    private var days: [Date] {
        CalendarView.visibleDays(mode: .month, selectedDay: month)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(UD.textPrimary)
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next month")
            }
            .buttonStyle(.plain)
            .foregroundStyle(UD.textTertiary)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(UD.textTertiary)
                        .accessibilityHidden(true)
                }
                ForEach(days, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
        .padding(12)
        .background(UD.bgCard, in: RoundedRectangle(cornerRadius: UD.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: UD.cardRadius, style: .continuous)
                .strokeBorder(UD.borderSecondary)
        )
        .task(id: [month.timeIntervalSince1970, Double(eventKit.changeCount)]) {
            await loadMarks()
        }
        .onChange(of: selectedDay) { _, day in
            if !calendar.isDate(day, equalTo: month, toGranularity: .month) {
                month = calendar.dateInterval(of: .month, for: day)?.start ?? day
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        return Button {
            onSelect(day)
        } label: {
            VStack(spacing: 1) {
                Text(day.formatted(.dateTime.day()))
                    .font(.caption.monospacedDigit().weight(isSelected || isToday ? .bold : .regular))
                    .frame(width: 24, height: 24)
                    .background {
                        if isSelected {
                            Circle().fill(UD.brand600)
                        } else if isToday {
                            Circle().fill(UD.brand50)
                        }
                    }
                    .foregroundStyle(
                        isSelected ? .white : isToday ? UD.brand700 : inMonth ? UD.textPrimary : UD.textQuaternary
                    )
                Circle()
                    .fill(UD.brand500)
                    .frame(width: 4, height: 4)
                    .opacity(markedDays.contains(day) ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func shift(_ amount: Int) {
        if let next = calendar.date(byAdding: .month, value: amount, to: month) {
            month = next
        }
    }

    private func loadMarks() async {
        guard let first = days.first, let last = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return }
        let marks = await eventKit.daysWithItems(from: first, to: end)
        guard !Task.isCancelled else { return }
        markedDays = marks
    }
}

// MARK: - Search

/// Results for the sidebar search: events and reminders from the next month or so,
/// then notes.
private struct MacSearchView: View {
    @Environment(EventKitService.self) private var eventKit
    let query: String
    let onOpenNote: (Note) -> Void

    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var results: [TimelineItem] = []
    @State private var isSearching = true

    private var matchingNotes: [Note] {
        notes.filter { $0.matches(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            MacScreenHeader(caption: "Search", title: "\u{201C}\(query)\u{201D}") { EmptyView() }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if !results.isEmpty {
                        UDListHeader(title: "Events and reminders", count: results.count)
                        ForEach(results) { item in
                            TimelineRow(item: item, showsDay: true) {
                                Task { await search() }
                            }
                        }
                    }
                    if !matchingNotes.isEmpty {
                        UDListHeader(title: "Notes", count: matchingNotes.count)
                            .padding(.top, results.isEmpty ? 0 : 12)
                        ForEach(matchingNotes) { note in
                            Button {
                                onOpenNote(note)
                            } label: {
                                UDCard {
                                    NoteRow(note: note)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(16)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, MacLayout.contentPadding)
                .padding(.bottom, MacLayout.contentPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay {
                if results.isEmpty && matchingNotes.isEmpty && !isSearching {
                    UDEmptyState(icon: "magnifyingglass", title: "No results", message: "Nothing matches \"\(query)\".")
                }
            }
        }
        .task(id: query) {
            // A new keystroke cancels the wait, so search runs once typing pauses.
            isSearching = true
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await search()
        }
        .task(id: eventKit.changeCount) {
            await search()
        }
    }

    private func search() async {
        guard eventKit.accessGranted else {
            isSearching = false
            return
        }
        let found = await eventKit.search(query)
        guard !Task.isCancelled else { return }
        results = found
        isSearching = false
    }
}
#endif
