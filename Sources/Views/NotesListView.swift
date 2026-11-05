import SwiftData
import SwiftUI

/// Every note kept in UnifiedDay, with pinned notes first. Works without Calendar
/// access, since notes don't live in Apple's apps.
struct NotesListView: View {
    /// Which folder the list shows: empty for all notes, `unfiledFolderID`, or a folder's uuid.
    /// The composer reads it so new notes land in the folder being viewed.
    static let folderKey = "notesFolderID"
    static let unfiledFolderID = "unfiled"

    enum Sort: String, CaseIterable, Identifiable {
        case edited = "Date Edited"
        case created = "Date Created"
        case title = "Title"
        var id: String { rawValue }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All Notes"
        case attached = "Attached to Items"
        case unattached = "Not Attached"
        var id: String { rawValue }
    }

    @Environment(EventKitService.self) private var eventKit
    @Environment(\.modelContext) private var modelContext
    @Query private var notes: [Note]
    @Query(sort: \NoteFolder.name) private var folders: [NoteFolder]
    @AppStorage(NotesListView.folderKey) private var folderID = ""
    @AppStorage("notesSort") private var sort = Sort.edited
    @AppStorage("notesFilter") private var filter = Filter.all
    /// The toggle at the top left: the notes list or the list of folders.
    @AppStorage("notesShowsFolders") private var showsFolders = false
    @State private var searchText = ""
    @State private var editingFolder: NoteFolder?
    @State private var isNamingFolder = false
    @State private var folderName = ""

    private var currentFolder: NoteFolder? {
        folders.first { $0.uuid.uuidString == folderID }
    }

    private var title: String {
        if showsFolders { return "Folders" }
        if folderID == Self.unfiledFolderID { return "No Folder" }
        return currentFolder?.name ?? "Notes"
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visible: [Note] {
        let query = trimmedSearch
        return notes
            .filter { note in
                switch folderID {
                case "": true
                case Self.unfiledFolderID: note.folder == nil
                default: note.folder?.uuid.uuidString == folderID
                }
            }
            .filter { note in
                switch filter {
                case .all: true
                case .attached: !(note.links ?? []).isEmpty
                case .unattached: (note.links ?? []).isEmpty
                }
            }
            .filter { query.isEmpty || $0.matches(query) }
            .sorted { a, b in
                switch sort {
                case .edited: a.updatedAt > b.updatedAt
                case .created: a.createdAt > b.createdAt
                case .title: a.displayTitle.localizedStandardCompare(b.displayTitle) == .orderedAscending
                }
            }
    }

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if showsFolders {
                    folderList
                } else {
                    noteList
                }
            }
            .navigationTitle(title)
            .searchable(text: $searchText, prompt: showsFolders ? "Search folders" : "Search notes")
            .toolbar { toolbar }
            .alert(editingFolder == nil ? "New Folder" : "Rename Folder", isPresented: $isNamingFolder) {
                TextField("Name", text: $folderName)
                Button("Cancel", role: .cancel) {}
                Button("Save") { saveFolderName() }
            } message: {
                Text("Deleting a folder later keeps its notes.")
            }
            .onChange(of: folders) {
                // The folder being viewed was deleted, here or on another device.
                if !folderID.isEmpty, folderID != Self.unfiledFolderID, currentFolder == nil {
                    folderID = ""
                }
            }
        }
    }

    private var noteList: some View {
        let pinned = visible.filter(\.isPinned)
        let others = visible.filter { !$0.isPinned }
        return List {
            if !pinned.isEmpty {
                Section("Pinned") {
                    ForEach(pinned, content: row)
                }
            }
            Section {
                ForEach(others, content: row)
            } header: {
                if !pinned.isEmpty {
                    Text("Notes")
                }
            }
        }
        .contentMargins(.bottom, ComposerButtonClearance.height, for: .scrollContent)
        .overlay {
            if notes.isEmpty {
                ContentUnavailableView(
                    "No notes yet",
                    systemImage: "note.text",
                    description: Text("Tap + to write one.")
                )
            } else if visible.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "No notes here",
                        systemImage: "folder",
                        description: Text("Try another folder or filter.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    /// Every folder with its note count. Tapping one opens its notes.
    private var folderList: some View {
        let shown = folders.filter { trimmedSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(trimmedSearch) }
        return List {
            if trimmedSearch.isEmpty {
                folderButton("All Notes", systemImage: "tray.full", count: notes.count, id: "")
            }
            ForEach(shown) { folder in
                folderButton(folder.name, systemImage: "folder", count: folder.notes?.count ?? 0, id: folder.uuid.uuidString)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            modelContext.delete(folder)
                            modelContext.saveNotes(reportingTo: eventKit)
                        }
                        Button("Rename", systemImage: "pencil") {
                            nameFolder(folder)
                        }
                        .tint(.orange)
                    }
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { nameFolder(folder) }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            modelContext.delete(folder)
                            modelContext.saveNotes(reportingTo: eventKit)
                        }
                    }
            }
            if trimmedSearch.isEmpty {
                folderButton("No Folder", systemImage: "tray", count: notes.filter { $0.folder == nil }.count, id: Self.unfiledFolderID)
            }
        }
        .contentMargins(.bottom, ComposerButtonClearance.height, for: .scrollContent)
        .overlay {
            if !trimmedSearch.isEmpty && shown.isEmpty {
                ContentUnavailableView.search(text: trimmedSearch)
            }
        }
    }

    private func folderButton(_ name: String, systemImage: String, count: Int, id: String) -> some View {
        Button {
            folderID = id
            showsFolders = false
        } label: {
            LabeledContent {
                Text("\(count)")
            } label: {
                Label(name, systemImage: systemImage)
            }
        }
        .foregroundStyle(.primary)
    }

    private func row(_ note: Note) -> some View {
        NavigationLink {
            NoteEditorView(note: note)
        } label: {
            NoteRow(note: note)
        }
        .swipeActions(edge: .leading) {
            Button {
                togglePin(note)
            } label: {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                delete(note)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin") {
                togglePin(note)
            }
            Menu("Move to Folder", systemImage: "folder") {
                Button("None") { move(note, to: nil) }
                ForEach(folders) { folder in
                    Button(folder.name) { move(note, to: folder) }
                }
            }
            if !note.shareText.isEmpty {
                ShareLink(item: note.shareText)
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                delete(note)
            }
        }
    }

    private func togglePin(_ note: Note) {
        note.isPinned.toggle()
        modelContext.saveNotes(reportingTo: eventKit)
    }

    private func move(_ note: Note, to folder: NoteFolder?) {
        note.folder = folder
        modelContext.saveNotes(reportingTo: eventKit)
    }

    private func delete(_ note: Note) {
        modelContext.delete(note)
        modelContext.saveNotes(reportingTo: eventKit)
    }

    private func nameFolder(_ folder: NoteFolder?) {
        editingFolder = folder
        folderName = folder?.name ?? ""
        isNamingFolder = true
    }

    private func saveFolderName() {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let editingFolder {
            editingFolder.name = trimmed
        } else {
            modelContext.insert(NoteFolder(name: trimmed))
        }
        modelContext.saveNotes(reportingTo: eventKit)
    }

    /// One half of the Notes and Folders toggle. The active one is tinted.
    private func viewButton(_ title: String, systemImage: String, showsFolders target: Bool) -> some View {
        let isActive = showsFolders == target
        return Button {
            showsFolders = target
        } label: {
            Label(title, systemImage: systemImage)
                .symbolVariant(isActive ? .fill : .none)
        }
        .labelStyle(.iconOnly)
        // Toolbar buttons take their color from tint, not foregroundStyle.
        .tint(isActive ? Color.accentColor : Color.secondary)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // Two plain buttons, not a segmented picker: the toolbar already draws a
        // glass capsule, and a picker inside it looked doubled and animated unevenly.
        ToolbarItemGroup(placement: .topBarLeading) {
            viewButton("Notes", systemImage: "note.text", showsFolders: false)
            viewButton("Folders", systemImage: "folder", showsFolders: true)
        }
        ToolbarItem(placement: .topBarTrailing) {
            if showsFolders {
                Button("New Folder", systemImage: "folder.badge.plus") {
                    nameFolder(nil)
                }
            } else {
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
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Pinned")
                }
                Text(note.displayTitle)
                    .lineLimit(1)
            }
            if !note.preview.isEmpty {
                Text(note.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Text(note.updatedAt.formatted(date: .abbreviated, time: .omitted))
                if let folder = note.folder {
                    HStack(spacing: 2) {
                        Image(systemName: "folder")
                        Text(folder.name)
                    }
                }
                if !(note.images ?? []).isEmpty {
                    Image(systemName: "photo")
                        .accessibilityLabel("Has images")
                }
                if !(note.links ?? []).isEmpty {
                    Image(systemName: "paperclip")
                        .accessibilityLabel("Attached to an event or reminder")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
