import SwiftUI

/// Reminders grouped by Apple Reminders list. Dateless and future items live here;
/// the Today tab only shows what is due.
struct RemindersListView: View {
    @Environment(EventKitService.self) private var eventKit
    @State private var grouped: [(list: String, items: [TimelineItem])] = []
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered, id: \.list) { group in
                    Section("\(group.list) (\(group.items.count))") {
                        ForEach(group.items) { item in
                            TimelineRow(item: item) {
                                Task { await load() }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reminders")
            .searchable(text: $searchText, prompt: "Search titles and notes")
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: eventKit.changeCount) {
                Task { await load() }
            }
        }
    }

    private var filtered: [(list: String, items: [TimelineItem])] {
        guard !searchText.isEmpty else { return grouped }
        return grouped.compactMap { group in
            let matches = group.items.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                    || ($0.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
            return matches.isEmpty ? nil : (group.list, matches)
        }
    }

    private func load() async {
        // All incomplete reminders, then keep dateless ones plus anything due
        // within the next 30 days. Grouped by list for the tab layout.
        let all = await eventKit.fetchAllIncompleteReminders()
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: 30, to: calendar.startOfDay(for: .now)) ?? .distantFuture
        let relevant = all.filter { item in
            guard let due = item.startDate else { return true }
            return due <= cutoff
        }

        let byList = Dictionary(grouping: relevant, by: \.sourceName)
        grouped = byList
            .map { (list: $0.key, items: EventKitService.sortItems($0.value)) }
            .sorted { $0.list < $1.list }
    }
}
