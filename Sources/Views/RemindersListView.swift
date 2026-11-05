import SwiftData
import SwiftUI

/// Reminders grouped by Apple Reminders list. Dateless and future items live here;
/// the Today tab only shows what is due.
struct RemindersListView: View {
    enum Sort: String, CaseIterable, Identifiable {
        case dueDate = "Due Date"
        case created = "Date Created"
        case title = "Title"
        var id: String { rawValue }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case overdue = "Overdue"
        case today = "Due Today"
        case scheduled = "Scheduled"
        case noDate = "No Date"
        var id: String { rawValue }

        func includes(_ item: TimelineItem) -> Bool {
            switch self {
            case .all: true
            case .overdue: item.isOverdue
            case .today: !item.isOverdue && item.startDate.map(Calendar.current.isDateInToday) == true
            case .scheduled: item.startDate != nil
            case .noDate: item.startDate == nil
            }
        }
    }

    private struct Group {
        let id: String
        let name: String
        var items: [TimelineItem]
    }

    @Environment(EventKitService.self) private var eventKit
    @Query private var notes: [Note]
    @State private var grouped: [Group] = []
    @State private var searchText = ""
    @State private var hasLoaded = false
    @State private var isNamingList = false
    @State private var newListName = ""
    @AppStorage("remindersSort") private var sort = Sort.dueDate
    @AppStorage("remindersFilter") private var filter = Filter.all

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if !eventKit.accessGranted {
                    AccessPromptView { Task { _ = await eventKit.requestAccess() } }
                } else {
                    reminderList
                }
            }
            .navigationTitle("Reminders")
            .searchable(text: $searchText, prompt: "Search titles and notes")
            .toolbar { toolbar }
            .alert("New List", isPresented: $isNamingList) {
                TextField("Name", text: $newListName)
                Button("Cancel", role: .cancel) {}
                Button("Create") { createList() }
            } message: {
                Text("The list is added to Apple Reminders too.")
            }
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: eventKit.changeCount) {
                Task { await load() }
            }
            .onChange(of: eventKit.accessGranted) {
                Task { await load() }
            }
        }
    }

    private var reminderList: some View {
        List {
            ForEach(filtered, id: \.id) { group in
                Section("\(group.name) (\(group.items.count))") {
                    if group.items.isEmpty {
                        Text("No reminders")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(group.items) { item in
                        TimelineRow(item: item, showsDay: true) {
                            Task { await load() }
                        } onRemove: { removed, target in
                            // Rescheduled reminders stay in their list, so only a delete removes one.
                            guard target == nil else { return }
                            for index in grouped.indices {
                                grouped[index].items.removeAll { $0.id == removed.id }
                            }
                        }
                    }
                }
            }
        }
        .contentMargins(.bottom, ComposerButtonClearance.height, for: .scrollContent)
        .overlay {
            if !hasLoaded {
                ProgressView()
            } else if grouped.isEmpty {
                ContentUnavailableView(
                    "No open reminders",
                    systemImage: "checklist",
                    description: Text("Tap + to add one.")
                )
            } else if filtered.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "Nothing \(filter.rawValue.lowercased())",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Try another filter.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if eventKit.accessGranted {
            ToolbarItem(placement: .topBarLeading) {
                Button("New List", systemImage: "folder.badge.plus") {
                    newListName = ""
                    isNamingList = true
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort by", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Show", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Image(systemName: filter == .all
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("Sort and filter")
            }
        }
    }

    /// Empty lists only show with no filter or search, so new lists appear right away.
    private var filtered: [Group] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let showEmpty = filter == .all && query.isEmpty
        // Reminders with an attached UnifiedDay note that matches, not just Apple notes.
        let noteLinks = query.isEmpty ? [] : notes.filter { $0.matches(query) }.flatMap { $0.links ?? [] }
        return grouped.compactMap { group in
            let matches = group.items
                .filter(filter.includes)
                .filter { item in
                    query.isEmpty
                        || item.title.localizedCaseInsensitiveContains(query)
                        || (item.notes?.localizedCaseInsensitiveContains(query) ?? false)
                        || noteLinks.contains { $0.matches(item) }
                }
            let sorted: [TimelineItem] = switch sort {
            case .dueDate: matches
            case .created: matches.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
            case .title: matches.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            }
            return sorted.isEmpty && !showEmpty ? nil : Group(id: group.id, name: group.name, items: sorted)
        }
    }

    private func createList() {
        let name = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if eventKit.createReminderList(named: name) {
            Task { await load() }
        }
    }

    private func load() async {
        guard eventKit.accessGranted else { return }
        defer { hasLoaded = true }
        // All incomplete reminders, then keep dateless ones plus anything due
        // within the next 30 days. Grouped by list for the tab layout.
        let all = await eventKit.fetchAllIncompleteReminders()
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: 30, to: calendar.startOfDay(for: .now)) ?? .distantFuture
        let relevant = all.filter { item in
            guard let due = item.startDate else { return true }
            return due <= cutoff
        }

        let byList = Dictionary(grouping: relevant, by: \.sourceID)
        grouped = eventKit.reminderLists()
            .map { list in
                Group(
                    id: list.calendarIdentifier,
                    name: list.title,
                    items: EventKitService.sortItems(byList[list.calendarIdentifier] ?? [])
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
