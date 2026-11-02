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
                Button("Attach Event or Reminder") {
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
            ItemPickerView(note: note)
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
        return [item.dayLabel, item.timeLabel, item.sourceName].compactMap { $0 }.joined(separator: ", ")
    }

    private func resolve() {
        item = eventKit.item(kind: link.kind, externalID: link.externalID, localID: link.localID)
        if let title = item?.title, title != link.title {
            link.title = title
        }
    }
}

/// Picks an event or reminder for a note. Shows today until you search.
struct ItemPickerView: View {
    @Environment(EventKitService.self) private var eventKit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let note: Note

    @State private var searchText = ""
    @State private var items: [TimelineItem] = []
    @State private var hasLoaded = false

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List(items) { item in
                Button {
                    attach(item)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .foregroundStyle(.primary)
                            Text([item.dayLabel, item.timeLabel].compactMap { $0 }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if note.isAttached(to: item) {
                            Image(systemName: "checkmark")
                                .accessibilityLabel("Attached")
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(note.isAttached(to: item))
            }
            .overlay {
                if !eventKit.accessGranted {
                    ContentUnavailableView(
                        "Calendar access needed",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Allow access to attach events and reminders.")
                    )
                } else if hasLoaded && items.isEmpty {
                    if trimmedSearch.isEmpty {
                        ContentUnavailableView(
                            "Nothing today",
                            systemImage: "magnifyingglass",
                            description: Text("Search for an event or reminder.")
                        )
                    } else {
                        ContentUnavailableView.search(text: trimmedSearch)
                    }
                }
            }
            .navigationTitle("Attach to Note")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search the next 30 days")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: trimmedSearch) {
                await load()
            }
        }
    }

    /// Debounced by the `.task(id:)` restart, like search on Today.
    private func load() async {
        guard eventKit.accessGranted else { return }
        let query = trimmedSearch
        if !query.isEmpty {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
        }
        let found = query.isEmpty
            ? await eventKit.fetchTimeline(for: .now)
            : await eventKit.search(query)
        guard !Task.isCancelled else { return }
        // A repeating event appears once per occurrence, but a note covers them all.
        var seen = Set<String>()
        items = found.filter { seen.insert($0.externalIdentifier.isEmpty ? $0.id : $0.externalIdentifier).inserted }
        hasLoaded = true
    }

    private func attach(_ item: TimelineItem) {
        let link = NoteLink(item: item)
        modelContext.insert(link)
        link.note = note
        note.updatedAt = .now
        modelContext.saveNotes(reportingTo: eventKit)
        dismiss()
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
        let link = NoteLink(item: item)
        modelContext.insert(link)
        link.note = note
        note.updatedAt = .now
        modelContext.saveNotes(reportingTo: eventKit)
        dismiss()
    }
}
