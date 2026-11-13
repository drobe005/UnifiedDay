#if os(macOS)
import SwiftUI

/// Reminders on the Mac: one column per Apple Reminders list, side by side.
struct MacRemindersView: View {
    typealias Sort = RemindersListView.Sort
    typealias Filter = RemindersListView.Filter

    @Environment(EventKitService.self) private var eventKit
    @State private var grouped: [RemindersListView.ListGroup] = []
    @State private var hasLoaded = false
    @State private var isNamingList = false
    @State private var newListName = ""
    // Same settings as the iPhone screen.
    @AppStorage("remindersSort") private var sort = Sort.dueDate
    @AppStorage("remindersFilter") private var filter = Filter.all

    private var filtered: [RemindersListView.ListGroup] {
        RemindersListView.arrange(grouped, filter: filter, sort: sort, query: "", noteLinks: [])
    }

    var body: some View {
        VStack(spacing: 0) {
            MacScreenHeader(title: "Reminders") {
                if eventKit.accessGranted {
                    Button {
                        newListName = ""
                        isNamingList = true
                    } label: {
                        Label("New List", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(UDSmallButtonStyle())
                    Menu {
                        Picker("Sort by", selection: $sort) {
                            ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Picker("Show", selection: $filter) {
                            ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        FilterChip(
                            icon: "line.3.horizontal.decrease",
                            text: filter == .all ? sort.rawValue : filter.rawValue
                        )
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Sort and filter")
                }
                MacNewButton()
            }
            content
        }
        .alert("New List", isPresented: $isNamingList) {
            TextField("Name", text: $newListName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { createList() }
        } message: {
            Text("The list is added to Apple Reminders too.")
        }
        .task { await load() }
        .onChange(of: eventKit.changeCount) {
            Task { await load() }
        }
        .onChange(of: eventKit.accessGranted) {
            Task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !eventKit.accessGranted {
            AccessPromptView { Task { _ = await eventKit.requestAccess() } }
        } else if !hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if grouped.isEmpty {
            UDEmptyState(icon: "checklist", title: "No open reminders", message: "Press Cmd N to add one.")
                .frame(maxHeight: .infinity)
        } else if filtered.isEmpty {
            UDEmptyState(
                icon: "line.3.horizontal.decrease",
                title: "Nothing \(filter.rawValue.lowercased())",
                message: "Try another filter."
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(filtered, id: \.id) { group in
                        column(group)
                    }
                }
                .padding(.horizontal, MacLayout.contentPadding)
                .padding(.bottom, MacLayout.contentPadding)
            }
        }
    }

    private func column(_ group: RemindersListView.ListGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let color = group.items.first?.sourceColor {
                    Circle().fill(color).frame(width: 10, height: 10)
                }
                UDSectionHeader(title: group.name, count: group.items.count)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            ScrollView {
                LazyVStack(spacing: 8) {
                    if group.items.isEmpty {
                        UDEmptyListRow(text: "No reminders")
                    }
                    ForEach(group.items) { item in
                        TimelineRow(item: item, showsDay: true) {
                            Task { await load() }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(UD.bgSubtle, in: RoundedRectangle(cornerRadius: UD.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: UD.cardRadius, style: .continuous)
                .strokeBorder(UD.borderSecondary)
        )
    }

    private func load() async {
        guard eventKit.accessGranted else { return }
        defer { hasLoaded = true }
        grouped = await RemindersListView.loadGroups(from: eventKit)
    }

    private func createList() {
        let name = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if eventKit.createReminderList(named: name) {
            Task { await load() }
        }
    }
}
#endif
