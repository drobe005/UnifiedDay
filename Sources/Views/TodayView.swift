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
    @State private var showingSymbolKey = false
    @State private var showingAttention = false
    @State private var searchText = ""
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var searchResults: [TimelineItem] = []
    @State private var isSearching = false
    /// Sections folded shut, saved as comma-separated section titles.
    @AppStorage("collapsedTodaySections") private var collapsedSections = ""
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
            .navigationTitle("Today")
            .searchable(text: $searchText, prompt: "Search items and notes")
            .udMinimizedSearch()
            .task(id: trimmedSearch) {
                await runSearch()
            }
            .toolbar {
                UDOverlineToolbarItem(text: Date.now.formatted(
                    .dateTime.weekday(typeSize.isAccessibilitySize ? .abbreviated : .wide).month(.abbreviated).day()
                ))
                // Pull down to refresh; the header keeps only the bell, as in Figma.
                if eventKit.accessGranted {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingAttention = true
                        } label: {
                            AttentionBell(count: attentionCount)
                        }
                        .tint(UD.textPrimary)
                        .accessibilityLabel("Needs attention, \(attentionCount) \(attentionCount == 1 ? "item" : "items")")
                    }
                    .udPlain()
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
            .sheet(isPresented: $showingAttention) {
                NeedsAttentionView()
                    .environment(eventKit)
            }
            .onChange(of: eventKit.attentionRequested, initial: true) { _, requested in
                // A tap on the Needs Attention widget.
                guard requested else { return }
                eventKit.attentionRequested = false
                if eventKit.accessGranted { showingAttention = true }
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
        // Onboarding only shows without access, so access on close means it was
        // just granted. The key to the timeline's marks opens next.
        .sheet(isPresented: $showingOnboarding, onDismiss: {
            if eventKit.accessGranted { showingSymbolKey = true }
        }) {
            OnboardingView()
                .environment(eventKit)
        }
        .sheet(isPresented: $showingSymbolKey) {
            SymbolKeyIntroView()
        }
    }

    private var timelineList: some View {
        List {
            ForEach(sections, id: \.title) { section in
                Section {
                    if !isCollapsed(section.title) {
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
                } header: {
                    // The day's summary rides in the first header, so it sits right
                    // under the title without an extra list gap.
                    VStack(alignment: .leading, spacing: 8) {
                        if section.title == sections.first?.title {
                            summaryLine
                        }
                        UDFoldableHeader(
                            title: section.title,
                            count: section.items.count,
                            isCollapsed: isCollapsed(section.title)
                        ) {
                            toggle(section.title)
                        }
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
                TimelineRow(item: item, showsDay: true, showsDivider: item.id != searchResults.last?.id) {
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
                        NoteCardLink(note: note, showsDivider: note !== matchingNotes.last)
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

    /// "4 events · 1 reminder left" as one gray line under the title.
    private var summaryLine: some View {
        let events = items.filter { $0.kind == .event }.count
        let reminders = items.count - events
        return Text("\(events) \(events == 1 ? "event" : "events") · \(reminders) \(reminders == 1 ? "task" : "tasks") left")
            .font(.subheadline)
            .foregroundStyle(UD.textTertiary)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(events) \(events == 1 ? "event" : "events"), \(reminders) \(reminders == 1 ? "task" : "tasks") left")
    }

    private var collapsedTitles: Set<String> {
        Set(collapsedSections.split(separator: ",").map(String.init))
    }

    private func isCollapsed(_ title: String) -> Bool {
        collapsedTitles.contains(title)
    }

    private func toggle(_ title: String) {
        var titles = collapsedTitles
        if titles.contains(title) { titles.remove(title) } else { titles.insert(title) }
        collapsedSections = titles.sorted().joined(separator: ",")
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
            title: "Nothing on the books",
            message: "No events or tasks today. Tap + to add one."
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

/// Bell for the Today toolbar, with a small red dot when something needs attention.
struct AttentionBell: View {
    let count: Int

    var body: some View {
        Image(systemName: "bell")
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Circle()
                        .fill(UD.errorFg)
                        .frame(width: 8, height: 8)
                        .offset(x: 1, y: -1)
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
                    title: "Calendar access needed",
                    message: "Turn on full access for Calendars and Reminders in iOS Settings.",
                    actionTitle: "Open Settings"
                ) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } else {
                UDEmptyState(
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
    /// Shows the calendar or list name under the title. Off where a heading already names it.
    var showsSource = true
    /// Draws the hairline under the row. Off for the last row of a group.
    var showsDivider = true
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
        if item.isRepeatingReminder { return "Delete this repeating task?" }
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
        // Marker at the far left, title and detail in the middle, time at the right.
        HStack(alignment: .top, spacing: 12) {
            marker
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? UD.textTertiary : UD.textPrimary)
                if showsSource || hasMarkers {
                    detail
                }
                // Large accessibility text needs the full width, so the time moves under.
                if typeSize.isAccessibilitySize, let trailingLabel {
                    timeText(trailingLabel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !typeSize.isAccessibilitySize, let trailingLabel {
                timeText(trailingLabel)
                    .padding(.top, 2)
            }
        }
        // Lets the color bar grow to the height of the text beside it.
        .fixedSize(horizontal: false, vertical: true)
        // 12 on the left lines the marker up under the section header text, as in Figma.
        .padding(.leading, 12)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if showsDivider { UDDivider() }
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
        .alert(deleteTitle, isPresented: $confirmingDelete) {
            if item.isRepeatingEvent {
                Button("Delete This Event Only", role: .destructive) { delete() }
                Button("Delete All Future Events", role: .destructive) { delete(includingFuture: true) }
            } else if item.isRepeatingReminder {
                if item.nextOccurrenceDate != nil {
                    Button("Delete This Task Only", role: .destructive) { skip() }
                }
                Button("Delete All Future Tasks", role: .destructive) { delete() }
            } else {
                Button("Delete", role: .destructive) { delete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(RepeatDeleteCopy.message(for: item))
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
        // Every list that shows these rows gets the plain look with no extra setup.
        .udPlainRow()
    }

    /// The event's calendar color as a thin bar, or the reminder's completion circle.
    @ViewBuilder
    private var marker: some View {
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
            RoundedRectangle(cornerRadius: 2)
                .fill(item.sourceColor)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 2)
                .frame(width: ReminderCheck.columnWidth, alignment: .leading)
                .accessibilityHidden(true)
        }
    }

    private var hasMarkers: Bool {
        item.repeatOption != .never || hasNote
    }

    /// Calendar or list name and small markers, in gray under the title.
    private var detail: some View {
        HStack(spacing: 4) {
            if showsSource {
                Text(item.sourceName)
                    .lineLimit(1)
            }
            if item.repeatOption != .never {
                Image(systemName: "repeat")
                    .accessibilityLabel("Repeats \(item.repeatLabel.lowercased())")
            }
            if hasNote {
                Image(systemName: "note.text")
                    .accessibilityLabel("Has a note")
            }
        }
        .font(.subheadline)
        .imageScale(.small)
        .foregroundStyle(UD.textTertiary)
    }

    /// Time at the right. Rows with no detail line use the larger size, like Reminders.
    private func timeText(_ label: String) -> some View {
        Text(label)
            .font(showsSource ? .caption.weight(.medium) : .subheadline)
            .monospacedDigit()
            .foregroundStyle(item.isOverdue ? UD.errorFg : UD.textTertiary)
            .lineLimit(1)
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

    /// Deletes only this occurrence of a repeating reminder by moving it to its next date.
    private func skip() {
        guard let next = item.nextOccurrenceDate else { return }
        onRemove(item, .day(next))
        eventKit.skipOccurrence(item)
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
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        UDToolbarCancelButton { dismiss() }
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

                VStack(alignment: .leading, spacing: 0) {
                    point("Reads your Apple Calendar so events show up in the timeline.", icon: "calendar")
                    UDDivider()
                    point("Reads your Apple Reminders so tasks sit next to events.", icon: "checklist")
                    UDDivider()
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
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// One permission line: a plain icon and one sentence.
    private func point(_ text: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(UD.textPrimary)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .foregroundStyle(UD.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
    }
}
