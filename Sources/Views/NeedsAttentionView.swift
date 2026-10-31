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
                    ContentUnavailableView(
                        "All caught up",
                        systemImage: "checkmark.circle",
                        description: Text("Nothing overdue or due today.")
                    )
                } else {
                    List {
                        section("Overdue", items: overdue)
                        section("Due today", items: dueToday)
                    }
                }
            }
            .navigationTitle("Needs Attention")
            .navigationBarTitleDisplayMode(.inline)
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
            Section(title) {
                ForEach(items) { item in
                    TimelineRow(item: item) {
                        Task { await load() }
                    }
                }
            }
        }
    }

    private func load() async {
        items = await eventKit.fetchNeedsAttention()
        hasLoaded = true
    }
}
