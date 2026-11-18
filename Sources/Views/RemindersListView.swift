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
        /// The list's color in Apple Reminders, for the dot in its heading.
        var color: Color?
        var canDelete = false
        var items: [TimelineItem]
    }

    @Environment(EventKitService.self) private var eventKit
    @Query private var notes: [Note]
    @State private var grouped: [Group] = []
    @State private var searchText = ""
    @State private var hasLoaded = false
    @State private var isNamingList = false
    @State private var newListName = ""
    @State private var listToDelete: Group?
    /// Lists folded shut, saved as comma-separated list identifiers.
    @AppStorage("collapsedReminderLists") private var collapsedLists = ""
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
            .udMinimizedSearch()
            .toolbar { toolbar }
            .alert("New List", isPresented: $isNamingList) {
                TextField("Name", text: $newListName)
                Button("Cancel", role: .cancel) {}
                Button("Create") { createList() }
            } message: {
                Text("The list is added to Apple Reminders too.")
            }
            .alert(
                "Delete \"\(listToDelete?.name ?? "")\"?",
                isPresented: Binding(get: { listToDelete != nil }, set: { if !$0 { listToDelete = nil } }),
                presenting: listToDelete
            ) { group in
                Button("Cancel", role: .cancel) {}
                Button("Delete List", role: .destructive) { deleteList(group) }
            } message: { _ in
                Text("Every reminder in it is deleted too, including in Apple Reminders.")
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
                Section {
                    if !isCollapsed(group) {
                        if group.items.isEmpty {
                            UDEmptyListRow(text: "No reminders")
                        }
                        ForEach(group.items) { item in
                            // The heading already names the list, so rows skip it.
                            TimelineRow(
                                item: item,
                                showsDay: true,
                                showsSource: false,
                                showsDivider: item.id != group.items.last?.id
                            ) {
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
                } header: {
                    header(for: group)
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .udScreenBackground()
        .contentMargins(.bottom, ComposerButtonClearance.height, for: .scrollContent)
        .overlay {
            if !hasLoaded {
                ProgressView()
            } else if grouped.isEmpty {
                UDEmptyState(title: "No open reminders", message: "Tap + to add one.")
            } else if filtered.isEmpty {
                if searchText.isEmpty {
                    UDEmptyState(
                        title: "Nothing \(filter.rawValue.lowercased())",
                        message: "Try another filter."
                    )
                } else {
                    UDEmptyState(
                        title: "No results",
                        message: "Nothing matches \"\(searchText)\"."
                    )
                }
            }
        }
    }

    /// Tap to fold a list open or shut. The menu holds Delete List.
    private func header(for group: Group) -> some View {
        let collapsed = isCollapsed(group)
        return HStack(spacing: 4) {
            UDFoldableHeader(
                title: group.name,
                count: group.items.count,
                dotColor: group.color,
                isCollapsed: collapsed,
                isDisabled: isSearching,
                showHint: "Shows this list's reminders",
                hideHint: "Hides this list's reminders"
            ) {
                toggle(group)
            }

            if group.canDelete {
                Menu {
                    Button("Delete List", systemImage: "trash", role: .destructive) {
                        listToDelete = group
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(UD.textTertiary)
                        .frame(width: 44, height: 32, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("\(group.name) options")
            }
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var collapsedIDs: Set<String> {
        Set(collapsedLists.split(separator: ",").map(String.init))
    }

    /// Search opens every list, so matches are never hidden.
    private func isCollapsed(_ group: Group) -> Bool {
        !isSearching && collapsedIDs.contains(group.id)
    }

    private func toggle(_ group: Group) {
        var ids = collapsedIDs
        if ids.contains(group.id) { ids.remove(group.id) } else { ids.insert(group.id) }
        collapsedLists = ids.sorted().joined(separator: ",")
    }

    private func deleteList(_ group: Group) {
        if eventKit.deleteReminderList(id: group.id) {
            grouped.removeAll { $0.id == group.id }
            var ids = collapsedIDs
            ids.remove(group.id)
            collapsedLists = ids.sorted().joined(separator: ",")
            Task { await load() }
        }
    }

    /// How many open reminders the tab holds, for the gray line above the title.
    private var openCount: Int {
        grouped.reduce(0) { $0 + $1.items.count }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if eventKit.accessGranted {
            if hasLoaded {
                UDOverlineToolbarItem(text: "\(openCount) open")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New List", systemImage: "folder.badge.plus") {
                        newListName = ""
                        isNamingList = true
                    }
                    Picker("Sort by", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Show", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Image(systemName: filter == .all
                        ? "line.3.horizontal.decrease"
                        : "line.3.horizontal.decrease.circle.fill")
                }
                .tint(UD.textPrimary)
                .accessibilityLabel("Lists, sort, and filter")
            }
            .udPlain()
        }
    }

    /// Empty lists only show with no filter or search, so new lists appear right away.
    private var filtered: [Group] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let showEmpty = filter == .all && query.isEmpty
        // Reminders with an attached UnifiedDay note that matches, not just Apple notes.
        let noteLinks = query.isEmpty ? [] : notes.filter { $0.matches(query) }.flatMap(\.attachedLinks)
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
            return sorted.isEmpty && !showEmpty
                ? nil
                : Group(id: group.id, name: group.name, color: group.color, canDelete: group.canDelete, items: sorted)
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
                    color: Color(list.cgColor),
                    canDelete: eventKit.canDeleteReminderList(id: list.calendarIdentifier),
                    items: EventKitService.sortItems(byList[list.calendarIdentifier] ?? [])
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
