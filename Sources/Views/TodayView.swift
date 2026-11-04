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
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingAttention = true
                        } label: {
                            AttentionBell(count: attentionCount)
                        }
                        .accessibilityLabel("Needs attention, \(attentionCount) \(attentionCount == 1 ? "item" : "items")")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
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
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)

            ForEach(sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        TimelineRow(item: item) {
                            Task { await load() }
                        } onRemove: { removed, target in
                            // Rescheduling to today keeps the row; the reload moves it.
                            if let target, Calendar.current.isDateInToday(target.day()) { return }
                            items.removeAll { $0.id == removed.id }
                        }
                    }
                }
            }
        }
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
                Section("Notes") {
                    ForEach(matchingNotes) { note in
                        NavigationLink {
                            NoteEditorView(note: note)
                        } label: {
                            NoteRow(note: note)
                        }
                    }
                }
            }
        }
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

    private var summary: String {
        let events = items.filter { $0.kind == .event }.count
        let reminders = items.count - events
        let eventText = "\(events) \(events == 1 ? "event" : "events")"
        let reminderText = "\(reminders) \(reminders == 1 ? "reminder" : "reminders") left"
        return "\(eventText), \(reminderText)"
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
        ContentUnavailableView(
            "Nothing on the books",
            systemImage: "checkmark.circle",
            description: Text("No events or reminders today. Tap + to add one.")
        )
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
                        .background(.red, in: Capsule())
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
        ContentUnavailableView {
            Label("Calendar access needed", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text(eventKit.accessNeedsSettings
                ? "Turn on full access for Calendars and Reminders in iOS Settings."
                : "UnifiedDay needs Calendar and Reminders access to build your timeline.")
        } actions: {
            if eventKit.accessNeedsSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
            }
        }
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
    @State private var confirmingRepeatDelete = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.noteLinkKeys) private var noteLinkKeys

    private var hasNote: Bool {
        noteLinkKeys.contains(item.externalIdentifier) || noteLinkKeys.contains(item.storeIdentifier)
    }

    private var trailingLabel: String? {
        if showsDay || item.isOverdue, let day = item.dayLabel {
            if item.isAllDay { return "\(day), all day" }
            return [day, item.timeLabel].compactMap { $0 }.joined(separator: ", ")
        }
        return item.timeLabel ?? (item.isAllDay ? "All day" : nil)
    }

    var body: some View {
        HStack(spacing: 12) {
            if item.kind == .reminder {
                Button {
                    eventKit.setReminderCompleted(item, completed: !item.isCompleted)
                    onChange()
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(item.isReadOnly)
                .accessibilityLabel(item.isCompleted ? "Mark \(item.title) not done" : "Mark \(item.title) done")
            } else {
                Circle()
                    .fill(item.sourceColor)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
            }

            // Large accessibility text needs the full width, so stack instead of side by side.
            let stacked = typeSize.isAccessibilitySize
            let layout = stacked
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    HStack(spacing: 4) {
                        Text(item.sourceName)
                        if item.repeatOption != .never {
                            Image(systemName: "repeat")
                                .accessibilityLabel("Repeats \(item.repeatOption.label.lowercased())")
                        }
                        if hasNote {
                            Image(systemName: "note.text")
                                .accessibilityLabel("Has a note")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if !stacked {
                    Spacer()
                }

                if let trailingLabel {
                    Text(trailingLabel)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(item.isOverdue ? Color.red : .secondary)
                        .multilineTextAlignment(stacked ? .leading : .trailing)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showingDetail = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens details")
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if item.kind == .reminder && !item.isReadOnly && !item.isCompleted {
                Button {
                    reschedule(to: .tomorrow)
                } label: {
                    Label("Tomorrow", systemImage: "sunrise")
                }
                .tint(.blue)

                Button {
                    reschedule(to: .nextWeek)
                } label: {
                    Label("Next week", systemImage: "calendar.badge.clock")
                }
                .tint(.indigo)

                if item.isOverdue {
                    Button {
                        reschedule(to: .today)
                    } label: {
                        Label("Today", systemImage: "sun.max")
                    }
                    .tint(.orange)
                }

                Button {
                    showingDatePicker = true
                } label: {
                    Label("Pick date", systemImage: "calendar")
                }
                .tint(.teal)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if item.isRepeatingEvent && !item.isReadOnly {
                // Not marked destructive: that role slides the row away before the
                // person picks which events to delete.
                Button {
                    confirmingRepeatDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            } else if !item.isReadOnly {
                Button(role: .destructive) {
                    delete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Delete this repeating event?", isPresented: $confirmingRepeatDelete, titleVisibility: .visible) {
            Button("Delete This Event Only", role: .destructive) { delete() }
            Button("Delete All Future Events", role: .destructive) { delete(includingFuture: true) }
        } message: {
            Text("It will also be removed from Apple Calendar.")
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

/// Picks a day to move a reminder to. Keeps the reminder's time of day.
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
                .padding(.horizontal)
                .navigationTitle("Move \(item.title)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Move") {
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
            VStack(alignment: .leading, spacing: 20) {
                Text("One timeline for your day")
                    .font(.largeTitle.bold())

                VStack(alignment: .leading, spacing: 12) {
                    Label("Reads your Apple Calendar so events show up in the timeline.", systemImage: "calendar")
                    Label("Reads your Apple Reminders so tasks sit next to events.", systemImage: "checklist")
                    Label("Everything stays on your device and in your iCloud. There is no server.", systemImage: "lock")
                }
                .foregroundStyle(.secondary)

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
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRequesting)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
