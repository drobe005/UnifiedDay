import SwiftUI

/// Everything the app icon badge counts: overdue reminders and reminders due today.
/// Shows what needs action now, not a history of past alerts.
struct NeedsAttentionView: View {
    @Environment(EventKitService.self) private var eventKit
    @Environment(\.dismiss) private var dismiss
    @State private var items: [TimelineItem] = []
    @State private var hasLoaded = false

    private var overdue: [TimelineItem] { items.filter(\.isOverdue) }
    private var dueToday: [TimelineItem] { items.filter { !$0.isOverdue } }

    var body: some View {
        NavigationStack {
            Group {
                if !hasLoaded {
                    ProgressView()
                } else if items.isEmpty {
                    UDEmptyState(
                        icon: "checkmark",
                        title: "All caught up",
                        message: "Nothing overdue or due today."
                    )
                } else {
                    List {
                        section("Overdue", items: overdue)
                        section("Due today", items: dueToday)
                    }
                    .listStyle(.plain)
                    .udListSectionSpacing(0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .udScreenBackground()
            .navigationTitle("Needs Attention")
            .udInlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: eventKit.changeCount) {
                Task { await load() }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, items: [TimelineItem]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    TimelineRow(item: item) {
                        Task { await load() }
                    } onRemove: { removed, target in
                        // Rescheduling to today keeps the row; the reload moves it.
                        if let target, Calendar.current.isDateInToday(target.day()) { return }
                        self.items.removeAll { $0.id == removed.id }
                    }
                }
            } header: {
                UDListHeader(title: title, count: items.count)
            }
        }
    }

    private func load() async {
        items = await eventKit.fetchNeedsAttention()
        hasLoaded = true
    }
}
