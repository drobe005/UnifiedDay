import SwiftUI

/// The core screen: one chronological timeline for the day.
/// Sections follow the spec sort rule: overdue, timed, all-day, due today without time.
struct TodayView: View {
    @Environment(EventKitService.self) private var eventKit
    @State private var items: [TimelineItem] = []
    @State private var isLoading = false
    @State private var showingOnboarding = false

    var body: some View {
        NavigationStack {
            Group {
                if !eventKit.accessGranted {
                    accessPrompt
                } else if items.isEmpty && !isLoading {
                    emptyState
                } else {
                    timelineList
                }
            }
            .navigationTitle(Date.now.formatted(date: .abbreviated, time: .omitted))
            .toolbar {
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
                } else {
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
            .onChange(of: eventKit.accessGranted) { _, granted in
                if granted {
                    showingOnboarding = false
                    Task { await load() }
                }
            }
            .onChange(of: eventKit.changeCount) {
                guard eventKit.accessGranted else { return }
                Task { await load() }
            }
        }
    }

    private var timelineList: some View {
        List {
            ForEach(sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        TimelineRow(item: item) {
                            Task { await load() }
                        }
                    }
                }
            }
        }
        .overlay {
            if isLoading { ProgressView().padding() }
        }
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
            description: Text("No events or reminders due today. Enjoy the clear runway, or add something.")
        )
    }

    private var accessPrompt: some View {
        ContentUnavailableView(
            "Calendar access needed",
            systemImage: "calendar.badge.exclamationmark",
            description: Text("UnifiedDay reads your Apple Calendar and Reminders to build the timeline. Nothing leaves your device.")
        )
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        items = await eventKit.fetchTimeline(for: Date.now)
    }
}

struct TimelineRow: View {
    @Environment(EventKitService.self) private var eventKit
    let item: TimelineItem
    let onChange: () -> Void
    @State private var showingDetail = false

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
                .accessibilityLabel(item.isCompleted ? "Mark not done" : "Mark done")
            } else {
                Circle()
                    .fill(item.sourceColor)
                    .frame(width: 10, height: 10)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                Text(item.sourceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let time = item.timeLabel {
                Text(time)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if item.isAllDay {
                Text("All day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !item.isReadOnly {
                Button(role: .destructive) {
                    eventKit.delete(item)
                    onChange()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showingDetail) {
            ItemDetailView(item: item, onChange: onChange)
                .environment(eventKit)
        }
    }

    private func reschedule(to target: EventKitService.RescheduleTarget) {
        eventKit.reschedule(item, to: target)
        onChange()
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
                        let granted = await eventKit.requestAccess()
                        isRequesting = false
                        if granted { dismiss() }
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
