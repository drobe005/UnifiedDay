import SwiftData
import SwiftUI

/// Edits one note. Changes save as you type, so there is no Save button.
struct NoteEditorView: View {
    @Environment(EventKitService.self) private var eventKit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let note: Note

    @State private var showingItemPicker = false
    @State private var confirmingDelete = false
    /// Deleting waits until the screen closes, so it never shows a deleted note.
    @State private var deleteOnClose = false

    var body: some View {
        Form {
            Section {
                TextField("Title", text: edit(\.title))
                    .font(.headline)
                TextField("Write something", text: edit(\.text), axis: .vertical)
                    .lineLimit(8...)
            } footer: {
                Text("Saved in UnifiedDay and your iCloud. Not visible in Apple's apps.")
            }

            Section("Attached to") {
                ForEach(note.attachedLinks) { link in
                    AttachedItemRow(link: link)
                }
                Button("Attach Events or Reminders") {
                    showingItemPicker = true
                }
            }

            Section {
                Button("Delete Note", role: .destructive) {
                    confirmingDelete = true
                }
            }
        }
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this note?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteOnClose = true
                dismiss()
            }
        } message: {
            Text("Events and reminders it's attached to won't change.")
        }
        .sheet(isPresented: $showingItemPicker) {
            ItemPickerView(isAttached: note.isAttached(to:)) { items in
                note.attach(items, in: modelContext)
                modelContext.saveNotes(reportingTo: eventKit)
            }
        }
        .onDisappear {
            if deleteOnClose {
                modelContext.delete(note)
            }
            modelContext.saveNotes(reportingTo: eventKit)
        }
    }

    /// Only the person's own edits change the date, not changes arriving from iCloud.
    private func edit(_ field: ReferenceWritableKeyPath<Note, String>) -> Binding<String> {
        Binding {
            note[keyPath: field]
        } set: { value in
            note[keyPath: field] = value
            note.updatedAt = .now
        }
    }
}

/// An event or reminder attached to a note. Tap to open it, swipe to detach it.
struct AttachedItemRow: View {
    @Environment(EventKitService.self) private var eventKit
    @Environment(\.modelContext) private var modelContext

    let link: NoteLink

    @State private var item: TimelineItem?
    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item?.title ?? link.title)
                    .foregroundStyle(item == nil ? .secondary : .primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(item == nil)
        .swipeActions(edge: .trailing) {
            Button("Detach", role: .destructive) {
                modelContext.delete(link)
                modelContext.saveNotes(reportingTo: eventKit)
            }
        }
        .sheet(isPresented: $showingDetail) {
            if let item {
                ItemDetailView(item: item) { resolve() }
            }
        }
        .task(id: eventKit.changeCount) {
            resolve()
        }
    }

    private var subtitle: String {
        guard let item else { return "Can't find this item. It may have been deleted." }
        return "\(item.scheduleLabel), \(item.sourceName)"
    }

    private func resolve() {
        item = eventKit.item(kind: link.kind, externalID: link.externalID, localID: link.localID)
        if let title = item?.title, title != link.title {
            link.title = title
        }
    }
}

/// Picks events and reminders for a note, split by tab. Stays open while you pick,
/// and hands back everything selected when you tap Done.
struct ItemPickerView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case events = "Events"
        case reminders = "Reminders"
        var id: String { rawValue }
    }

    @Environment(EventKitService.self) private var eventKit
    @Environment(\.dismiss) private var dismiss

    /// Items that are already attached show as checked and can't be picked again.
    let isAttached: (TimelineItem) -> Bool
    let onDone: ([TimelineItem]) -> Void

    @State private var tab = Tab.events
    @State private var searchText = ""
    @State private var items: [TimelineItem] = []
    @State private var selected: [String: TimelineItem] = [:]
    @State private var hasLoaded = false

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleItems: [TimelineItem] {
        items.filter { item in
            (item.kind == .event) == (tab == .events)
                && (trimmedSearch.isEmpty
                    || item.title.localizedCaseInsensitiveContains(trimmedSearch)
                    || (item.notes?.localizedCaseInsensitiveContains(trimmedSearch) ?? false))
        }
    }

    var body: some View {
        NavigationStack {
            List(visibleItems) { item in
                row(item)
            }
            .safeAreaInset(edge: .top) {
                Picker("Type", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .overlay {
                if !eventKit.accessGranted {
                    ContentUnavailableView(
                        "Calendar access needed",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Allow access to attach events and reminders.")
                    )
                } else if hasLoaded && visibleItems.isEmpty {
                    if trimmedSearch.isEmpty {
                        ContentUnavailableView(
                            tab == .events ? "No upcoming events" : "No open reminders",
                            systemImage: tab == .events ? "calendar" : "checklist",
                            description: Text("Nothing to attach here in the next 30 days.")
                        )
                    } else {
                        ContentUnavailableView.search(text: trimmedSearch)
                    }
                }
            }
            .navigationTitle(selected.isEmpty ? "Attach" : "\(selected.count) Selected")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search the next 30 days")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(Array(selected.values))
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .task {
                await load()
            }
        }
    }

    private func row(_ item: TimelineItem) -> some View {
        let attached = isAttached(item)
        let isChecked = attached || selected[item.linkKey] != nil
        return Button {
            if selected.removeValue(forKey: item.linkKey) == nil {
                selected[item.linkKey] = item
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChecked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                    Text(attached ? "Already attached" : item.scheduleLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(attached)
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }

    private func load() async {
        guard eventKit.accessGranted else { return }
        let found = await eventKit.upcomingItems()
        // A repeating event appears once per occurrence, but a note covers them all.
        var seen = Set<String>()
        items = found.filter { seen.insert($0.linkKey).inserted }
        hasLoaded = true
    }
}

/// Notes attached to one event or reminder, shown in its details. The screen
/// around it shows the sheets, since adding a row here would close one shown from a row.
struct AttachedNotesSection: View {
    @Query private var links: [NoteLink]

    let item: TimelineItem
    let onNewNote: () -> Void
    let onAttachExisting: () -> Void

    private var notes: [Note] {
        var seen = Set<PersistentIdentifier>()
        return links
            .filter { $0.matches(item) }
            .compactMap(\.note)
            .filter { seen.insert($0.persistentModelID).inserted }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        Section("Attached notes") {
            ForEach(notes) { note in
                NavigationLink {
                    NoteEditorView(note: note)
                } label: {
                    NoteRow(note: note)
                }
            }
            Button("New Note", action: onNewNote)
            Button("Attach Existing Note", action: onAttachExisting)
        }
    }
}

/// Picks an existing note to attach to an event or reminder.
struct NotePickerView: View {
    @Environment(EventKitService.self) private var eventKit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]

    let item: TimelineItem

    @State private var searchText = ""

    private var available: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.filter { !$0.isAttached(to: item) && (query.isEmpty || $0.matches(query)) }
    }

    var body: some View {
        NavigationStack {
            List(available) { note in
                Button {
                    attach(note)
                } label: {
                    NoteRow(note: note)
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if available.isEmpty {
                    if searchText.isEmpty {
                        ContentUnavailableView(
                            "No notes to attach",
                            systemImage: "note.text",
                            description: Text("Notes you write will show up here.")
                        )
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
            .navigationTitle("Attach Note")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search notes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func attach(_ note: Note) {
        note.attach([item], in: modelContext)
        modelContext.saveNotes(reportingTo: eventKit)
        dismiss()
    }
}
