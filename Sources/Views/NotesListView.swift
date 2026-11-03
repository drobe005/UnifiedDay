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
    @State private var searchText = ""
    @State private var showingFolders = false

    private var currentFolder: NoteFolder? {
        folders.first { $0.uuid.uuidString == folderID }
    }

    private var title: String {
        if folderID == Self.unfiledFolderID { return "No Folder" }
        return currentFolder?.name ?? "Notes"
    }

    private var visible: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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
            let pinned = visible.filter(\.isPinned)
            let others = visible.filter { !$0.isPinned }
            List {
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
            .navigationTitle(title)
            .searchable(text: $searchText, prompt: "Search notes")
            .toolbar { toolbar }
            .sheet(isPresented: $showingFolders) {
                FolderManagerView()
                    .environment(eventKit)
            }
            .onChange(of: folders) {
                // The folder being viewed was deleted, here or on another device.
                if !folderID.isEmpty, folderID != Self.unfiledFolderID, currentFolder == nil {
                    folderID = ""
                }
            }
        }
    }

    private func row(_ note: Note) -> some View {
        NavigationLink {
            NoteEditorView(note: note)
        } label: {
            NoteRow(note: note)
        }
        .swipeActions(edge: .leading) {
            Button {
                note.isPinned.toggle()
                modelContext.saveNotes(reportingTo: eventKit)
            } label: {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                modelContext.delete(note)
                modelContext.saveNotes(reportingTo: eventKit)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Folder", selection: $folderID) {
                    Label("All Notes", systemImage: "tray.full").tag("")
                    ForEach(folders) { folder in
                        Label(folder.name, systemImage: "folder").tag(folder.uuid.uuidString)
                    }
                    Label("No Folder", systemImage: "tray").tag(Self.unfiledFolderID)
                }
                Divider()
                Button("Manage Folders", systemImage: "folder.badge.gearshape") {
                    showingFolders = true
                }
            } label: {
                Image(systemName: "folder")
            }
            .accessibilityLabel("Folders")
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

/// Create, rename, and delete note folders. Deleting a folder keeps its notes.
struct FolderManagerView: View {
    @Environment(EventKitService.self) private var eventKit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \NoteFolder.name) private var folders: [NoteFolder]

    @State private var editing: NoteFolder?
    @State private var isNaming = false
    @State private var name = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(folders) { folder in
                    Button {
                        editing = folder
                        name = folder.name
                        isNaming = true
                    } label: {
                        LabeledContent {
                            Text("\(folder.notes?.count ?? 0)")
                        } label: {
                            Label(folder.name, systemImage: "folder")
                        }
                    }
                    .foregroundStyle(.primary)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            modelContext.delete(folder)
                            modelContext.saveNotes(reportingTo: eventKit)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .overlay {
                if folders.isEmpty {
                    ContentUnavailableView(
                        "No folders yet",
                        systemImage: "folder",
                        description: Text("Tap the folder button at the top to make one.")
                    )
                }
            }
            .navigationTitle("Folders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("New Folder", systemImage: "folder.badge.plus") {
                        editing = nil
                        name = ""
                        isNaming = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(editing == nil ? "New Folder" : "Rename Folder", isPresented: $isNaming) {
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button("Save") { saveName() }
            } message: {
                Text("Deleting a folder later keeps its notes.")
            }
        }
    }

    private func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let editing {
            editing.name = trimmed
        } else {
            modelContext.insert(NoteFolder(name: trimmed))
        }
        modelContext.saveNotes(reportingTo: eventKit)
    }
}
