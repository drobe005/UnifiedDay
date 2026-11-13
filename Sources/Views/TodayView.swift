import SwiftData
import SwiftUI

/// The core screen: one chronological timeline for the day.
/// Sections follow the spec sort rule: overdue, timed, all-day, due today without time.
struct TodayView: View {
    @Environment(EventKitService.self) private var eventKit
    @State private var items: [TimelineItem] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var showingOnboarding = false
    @State private var showingAttention = false
    @State private var searchText = ""
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var searchResults: [TimelineItem] = []
    @State private var isSearching = false
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]

    private var matchingNotes: [Note] {
        notes.filter { $0.matches(trimmedSearch) }
    }

    /// Matches the app icon badge: the timeline's reminders are all overdue or due today.
    private var attentionCount: Int {
        items.filter { $0.kind == .reminder }.count
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Group {
                if !eventKit.accessGranted {
                    AccessPromptView { showingOnboarding = true }
                } else if !trimmedSearch.isEmpty {
                    searchList
                } else if !hasLoaded {
                    ProgressView()
                } else if items.isEmpty {
                    emptyState
                } else {
                    timelineList
                }
            }
            .navigationTitle(Date.now.formatted(
                .dateTime.weekday(typeSize.isAccessibilitySize ? .abbreviated : .wide).month(.abbreviated).day()
            ))
            .searchable(text: $searchText, prompt: "Search items and notes")
            .task(id: trimmedSearch) {
                await runSearch()
            }
            .toolbar {
                if eventKit.accessGranted {
                    ToolbarItem(placement: .udTrailing) {
                        Button {
                            showingAttention = true
                        } label: {
                            AttentionBell(count: attentionCount)
                        }
                        .accessibilityLabel("Needs attention, \(attentionCount) \(attentionCount == 1 ? "item" : "items")")
                    }
                }
                ToolbarItem(placement: .udTrailing) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
            }
            .task {
                if eventKit.accessGranted {
                    await load()
                } else if !eventKit.accessNeedsSettings {
                    showingOnboarding = true
                }
            }
            .refreshable {
                await load()
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingView()
                    .environment(eventKit)
            }
            .sheet(isPresented: $showingAttention) {
                NeedsAttentionView()
                    .environment(eventKit)
            }
            .onChange(of: eventKit.accessGranted) { _, granted in
                if granted {
                    showingOnboarding = false
                    Task { await load() }
                }
            }
            .onChange(of: eventKit.changeCount) {
                guard eventKit.accessGranted else { return }
                Task {
                    await load()
                    await runSearch()
                }
            }
        }
    }

    private var timelineList: some View {
        List {
            ForEach(sections, id: \.title) { section in
                Section {
                    ForEach(section.items) { item in
                        TimelineRow(item: item) {
                            Task { await load() }
                        } onRemove: { removed, target in
                            // Rescheduling to today keeps the row; the reload moves it.
                            if let target, Calendar.current.isDateInToday(target.day()) { return }
                            items.removeAll { $0.id == removed.id }
                        }
                    }
                } header: {
                    // The day's summary rides in the first header, so it sits right
                    // under the search bar without an extra list gap.
                    VStack(alignment: .leading, spacing: 12) {
                        if section.title == sections.first?.title {
                            summaryBadges
                                .padding(.top, 4)
                        }
                        UDListHeader(title: section.title, count: section.items.count)
                    }
                }
            }
        }
        .listStyle(.plain)
        .udScreenBackground()
        .contentMargins(.bottom, ComposerButtonClearance.height, for: .scrollContent)
        .overlay {
            if isLoading { ProgressView().padding() }
        }
    }

    private var searchList: some View {
        List {
            ForEach(searchResults) { item in
                TimelineRow(item: item, showsDay: true) {
                    Task { await load() }
                } onRemove: { removed, target in
                    // Search covers many days, so only a delete takes the row out.
                    guard target == nil else { return }
                    searchResults.removeAll { $0.id == removed.id }
                }
            }
            if !matchingNotes.isEmpty {
                Section {
                    ForEach(matchingNotes) { note in
                        NoteCardLink(note: note)
                    }
                } header: {
                    UDListHeader(title: "Notes", count: matchingNotes.count)
                }
            }
        }
        .listStyle(.plain)
        .udScreenBackground()
        .contentMargins(.bottom, ComposerButtonClearance.height, for: .scrollContent)
        .overlay {
            if searchResults.isEmpty && matchingNotes.isEmpty && !isSearching {
                ContentUnavailableView.search(text: trimmedSearch)
            }
        }
    }

    /// Debounced by the `.task(id:)` restart: a new keystroke cancels the sleep.
    private func runSearch() async {
        let query = trimmedSearch
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        let results = await eventKit.search(query)
        guard !Task.isCancelled else { return }
        searchResults = results
        isSearching = false
    }

    /// "4 events" and "1 reminder left" as badges under the search bar.
    private var summaryBadges: some View {
        let events = items.filter { $0.kind == .event }.count
        let reminders = items.count - events
        return HStack(spacing: 8) {
            UDBadge(text: "\(events) \(events == 1 ? "event" : "events")", tone: .brand, dot: true)
            UDBadge(
                text: "\(reminders) \(reminders == 1 ? "reminder" : "reminders") left",
                tone: reminders > 0 ? .warning : .gray,
                dot: true
            )
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var sections: [(title: String, items: [TimelineItem])] {
        let overdue = items.filter(\.isOverdue)
        let timed = items.filter { !$0.isOverdue && $0.isTimed }
        let allDay = items.filter { !$0.isOverdue && $0.isAllDay }
        let dateless = items.filter { !$0.isOverdue && !$0.isTimed && !$0.isAllDay }
        return [
            ("Overdue", overdue),
            ("Timed", timed),
            ("All day", allDay),
            ("Due today", dateless),
        ].filter { !$0.items.isEmpty }
    }

    private var emptyState: some View {
        UDEmptyState(
            icon: "calendar.badge.checkmark",
            title: "Nothing on the books",
            message: "No events or reminders today. Tap + to add one."
        )
        .frame(maxHeight: .infinity)
        .background(UD.bgScreen)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        items = await eventKit.fetchTimeline(for: Date.now)
        hasLoaded = true
        await eventKit.refreshBadge()
    }
}

/// Bell with a count, for the Today toolbar.
struct AttentionBell: View {
    let count: Int

    var body: some View {
        Image(systemName: "bell")
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(UD.errorFg, in: Capsule())
                        .fixedSize()
                        .offset(x: 9, y: -9)
                }
            }
    }
}

/// Extra scroll room so the floating + button never covers the last row.
enum ComposerButtonClearance {
    static let height: CGFloat = 88
}

/// Shown when Calendar or Reminders access is missing. Never a dead end: it either
/// restarts onboarding or links to iOS Settings when only Settings can fix it.
struct AccessPromptView: View {
    @Environment(EventKitService.self) private var eventKit
    let onContinue: () -> Void

    var body: some View {
        Group {
            if eventKit.accessNeedsSettings {
                UDEmptyState(
                    icon: "lock",
                    title: "Calendar access needed",
                    message: "Turn on full access for Calendars and Reminders in \(Platform.settingsName).",
                    actionTitle: "Open Settings"
                ) {
                    Platform.openAppSettings()
                }
            } else {
                UDEmptyState(
                    icon: "lock",
                    title: "Calendar access needed",
                    message: "UnifiedDay needs Calendar and Reminders access to build your timeline.",
                    actionTitle: "Continue",
                    action: onContinue
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UD.bgScreen)
    }
}

struct TimelineRow: View {
    @Environment(EventKitService.self) private var eventKit
    let item: TimelineItem
    /// Shows the day next to the time, for lists that span more than today.
    var showsDay = false
    let onChange: () -> Void
    /// Called before a swipe changes the item: with nil for a delete, or with where a
    /// reschedule moves it. The list removes the row right away if it no longer belongs,
    /// because a full swipe crashes the list when the row is still there after the swipe.
    var onRemove: (TimelineItem, EventKitService.RescheduleTarget?) -> Void = { _, _ in }
    @State private var showingDetail = false
    @State private var showingDatePicker = false
    @State private var confirmingDelete = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.noteLinkKeys) private var noteLinkKeys

    private var hasNote: Bool {
        noteLinkKeys.contains(item.externalIdentifier) || noteLinkKeys.contains(item.storeIdentifier)
    }

    /// Events and reminders can both move to another day. Completed reminders and
    /// items from read-only calendars or lists can't.
    private var canMove: Bool {
        !item.isReadOnly && !item.isCompleted && (item.kind == .reminder || item.startDate != nil)
    }

    private var deleteTitle: String {
        if item.isRepeatingEvent { return "Delete this repeating event?" }
        return "Delete \"\(item.title)\"?"
    }

    private var trailingLabel: String? {
        if showsDay || item.isOverdue, let day = item.dayLabel {
            if item.isAllDay { return "\(day), all day" }
            return [day, item.timeLabel].compactMap { $0 }.joined(separator: ", ")
        }
        return item.timeLabel ?? (item.isAllDay ? "All day" : nil)
    }

    var body: some View {
        UDCard {
            // The checkbox's 44 pt tap area already adds room, so reminders need less spacing.
            HStack(spacing: item.kind == .reminder ? 2 : 12) {
                if item.kind == .reminder {
                    Button {
                        toggleCompleted()
                    } label: {
                        ReminderCheck(isCompleted: item.isCompleted)
                    }
                    .buttonStyle(.plain)
                    .disabled(item.isReadOnly)
                    .accessibilityLabel(item.isCompleted ? "Mark \(item.title) not done" : "Mark \(item.title) done")
                } else {
                    // The event's calendar color, as a stripe down the card's edge.
                    RoundedRectangle(cornerRadius: 2)
                        .fill(item.sourceColor)
                        .frame(width: 4)
                        .frame(maxHeight: .infinity)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.body.weight(.semibold))
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? UD.textTertiary : UD.textPrimary)
                    meta
                }
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 12)
            // The checkbox has a 44 pt tap area, so reminders need less padding to line up.
            .padding(.leading, item.kind == .event ? 12 : 4)
            .padding(.trailing, 16)
        }
        .contentShape(Rectangle())
        .onTapGesture { showingDetail = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens details")
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if canMove {
                Button {
                    reschedule(to: .tomorrow)
                } label: {
                    Label("Tomorrow", systemImage: "sunrise")
                }
                .tint(UD.brand600)

                Button {
                    reschedule(to: .nextWeek)
                } label: {
                    Label("Next week", systemImage: "calendar.badge.clock")
                }
                .tint(UD.brand700)

                if item.isOverdue {
                    Button {
                        reschedule(to: .today)
                    } label: {
                        Label("Today", systemImage: "sun.max")
                    }
                    .tint(UD.orange500)
                }

                Button {
                    showingDatePicker = true
                } label: {
                    Label("Pick date", systemImage: "calendar")
                }
                .tint(UD.textTertiary)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !item.isReadOnly {
                // Asks first, so a stray swipe can't remove something from Apple
                // Calendar or Reminders. Not marked destructive: that role slides the
                // row away before the person answers.
                Button {
                    confirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(UD.errorFg)
            }
        }
        .contextMenu {
            Button("Open", systemImage: "info.circle") { showingDetail = true }
            if item.kind == .reminder && !item.isReadOnly {
                Button(item.isCompleted ? "Mark Not Done" : "Mark Done",
                       systemImage: item.isCompleted ? "circle" : "checkmark.circle") {
                    toggleCompleted()
                }
            }
            if canMove {
                Section("Move to") {
                    if item.isOverdue {
                        Button("Today", systemImage: "sun.max") { reschedule(to: .today) }
                    }
                    Button("Tomorrow", systemImage: "sunrise") { reschedule(to: .tomorrow) }
                    Button("Next week", systemImage: "calendar.badge.clock") { reschedule(to: .nextWeek) }
                    Button("Pick date", systemImage: "calendar") { showingDatePicker = true }
                }
            }
            if !item.isReadOnly {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    confirmingDelete = true
                }
            }
        }
        .confirmationDialog(deleteTitle, isPresented: $confirmingDelete, titleVisibility: .visible) {
            if item.isRepeatingEvent {
                Button("Delete This Event Only", role: .destructive) { delete() }
                Button("Delete All Future Events", role: .destructive) { delete(includingFuture: true) }
            } else {
                Button("Delete", role: .destructive) { delete() }
            }
        } message: {
            Text("It will also be removed from Apple \(item.kind == .reminder ? "Reminders" : "Calendar").")
        }
        .sheet(isPresented: $showingDetail) {
            ItemDetailView(item: item, onChange: onChange)
                .environment(eventKit)
        }
        .sheet(isPresented: $showingDatePicker) {
            RescheduleDateSheet(item: item) { day in
                reschedule(to: .day(day))
            }
            .presentationDetents([.medium, .large])
        }
        // Every list that shows these rows gets the card look with no extra setup.
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: UD.screenPadding, bottom: 4, trailing: UD.screenPadding))
    }

    /// Time, list or calendar, and small markers, under the title.
    private var meta: some View {
        // Large accessibility text needs the full width, so stack instead of side by side.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: 6))
        return layout {
            if let trailingLabel {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .accessibilityHidden(true)
                    Text(trailingLabel)
                        .monospacedDigit()
                }
                .foregroundStyle(item.isOverdue ? UD.errorFg : UD.textSecondary)
                if !typeSize.isAccessibilitySize {
                    Text("•")
                        .foregroundStyle(UD.textQuaternary)
                        .accessibilityHidden(true)
                }
            }
            HStack(spacing: 4) {
                Text(item.sourceName)
                    .lineLimit(1)
                if item.repeatOption != .never {
                    Image(systemName: "repeat")
                        .accessibilityLabel("Repeats \(item.repeatOption.label.lowercased())")
                }
                if hasNote {
                    Image(systemName: "note.text")
                        .accessibilityLabel("Has a note")
                }
            }
            .foregroundStyle(UD.textSecondary)
        }
        .font(.subheadline)
    }

    private func toggleCompleted() {
        eventKit.setReminderCompleted(item, completed: !item.isCompleted)
        onChange()
    }

    private func delete(includingFuture: Bool = false) {
        onRemove(item, nil)
        eventKit.delete(item, includingFuture: includingFuture)
        onChange()
    }

    private func reschedule(to target: EventKitService.RescheduleTarget) {
        onRemove(item, target)
        eventKit.reschedule(item, to: target)
        onChange()
    }
}

/// Picks a day to move an event or reminder to. Keeps its time of day.
struct RescheduleDateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: TimelineItem
    let onPick: (Date) -> Void
    @State private var day: Date

    init(item: TimelineItem, onPick: @escaping (Date) -> Void) {
        self.item = item
        self.onPick = onPick
        _day = State(initialValue: item.startDate ?? .now)
    }

    var body: some View {
        NavigationStack {
            DatePicker("Day", selection: $day, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(UD.brand600)
                .padding(.horizontal)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(UD.bgScreen)
                .navigationTitle("Move \(item.title)")
                .udInlineTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        UDToolbarConfirmButton(title: "Move") {
                            onPick(day)
                            dismiss()
                        }
                    }
                }
        }
    }
}

/// First-run permissions explainer. Plain language, one sentence per permission.
struct OnboardingView: View {
    @Environment(EventKitService.self) private var eventKit
    @Environment(\.dismiss) private var dismiss
    @State private var isRequesting = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(
                        LinearGradient(colors: [UD.brand500, UD.brand700], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .accessibilityHidden(true)

                Text("One timeline for your day")
                    .font(.largeTitle.bold())
                    .foregroundStyle(UD.textPrimary)

                VStack(alignment: .leading, spacing: 16) {
                    point("Reads your Apple Calendar so events show up in the timeline.", icon: "calendar")
                    point("Reads your Apple Reminders so tasks sit next to events.", icon: "checklist", accent: true)
                    point("Everything stays on your device and in your iCloud. There is no server.", icon: "lock")
                }

                Spacer()

                Button {
                    Task {
                        isRequesting = true
                        _ = await eventKit.requestAccess()
                        isRequesting = false
                        // If refused, the prompt behind this sheet links to Settings.
                        dismiss()
                    }
                } label: {
                    Text(isRequesting ? "Requesting..." : "Continue")
                }
                .buttonStyle(UDPrimaryButtonStyle(fullWidth: true))
                .disabled(isRequesting)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(UD.bgScreen)
            .udInlineTitle()
        }
    }

    /// One permission line: a small tinted icon tile and one sentence.
    private func point(_ text: String, icon: String, accent: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(accent ? UD.orange700 : UD.brand600)
                .frame(width: 32, height: 32)
                .background(accent ? UD.orange100 : UD.brand100, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .foregroundStyle(UD.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
