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
    @Environment(\.lastDeletedNote) private var lastDeletedNote
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
    /// The note or folder waiting on the delete box.
    @State private var noteToDelete: Note?
    @State private var folderToDelete: NoteFolder?

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
                case .attached: note.hasItemLinks
                case .unattached: !note.hasItemLinks
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
            .udMinimizedSearch()
            .toolbar { toolbar }
            .alert(editingFolder == nil ? "New Folder" : "Rename Folder", isPresented: $isNamingFolder) {
                TextField("Name", text: $folderName)
                Button("Cancel", role: .cancel) {}
                Button("Save") { saveFolderName() }
            } message: {
                Text("Deleting a folder later keeps its notes.")
            }
            .alert("Delete this note?", isPresented: isPresenting($noteToDelete), presenting: noteToDelete) { note in
                Button("Delete", role: .destructive) { delete(note) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Events and tasks it's attached to won't change.")
            }
            .alert("Delete this folder?", isPresented: isPresenting($folderToDelete), presenting: folderToDelete) { folder in
                Button("Delete", role: .destructive) {
                    modelContext.delete(folder)
                    modelContext.saveNotes(reportingTo: eventKit)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Its notes stay, under No Folder.")
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
                Section {
                    ForEach(pinned) { row($0, isLast: $0 === pinned.last) }
                } header: {
                    UDListHeader(title: "Pinned")
                }
            }
            Section {
                ForEach(others) { row($0, isLast: $0 === others.last) }
            } header: {
                if !pinned.isEmpty && !others.isEmpty {
                    UDListHeader(title: "Notes")
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .udScreenBackground()
        .contentMargins(.bottom, ComposerButtonClearance.height, for: .scrollContent)
        .overlay {
            if notes.isEmpty {
                UDEmptyState(title: "No notes yet", message: "Tap + to write one.")
            } else if visible.isEmpty {
                if searchText.isEmpty {
                    UDEmptyState(title: "No notes here", message: "Try another folder or filter.")
                } else {
                    searchEmptyState(searchText)
                }
            }
        }
    }

    private func searchEmptyState(_ text: String) -> some View {
        UDEmptyState(title: "No results", message: "Nothing matches \"\(text)\".")
    }

    /// Every folder with its note count. Tapping one opens its notes.
    private var folderList: some View {
        let shown = folders.filter { trimmedSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(trimmedSearch) }
        return List {
            // A section with a small gap as its heading, so no line sits above the first row.
            Section {
                if trimmedSearch.isEmpty {
                    folderButton("All Notes", count: notes.count, id: "")
                }
                ForEach(shown) { folder in
                    folderButton(folder.name, count: folder.notes?.count ?? 0, id: folder.uuid.uuidString)
                        .swipeActions(edge: .trailing) {
                            // Not marked destructive: that role slides the row away
                            // before the person answers.
                            Button("Delete", systemImage: "trash") {
                                folderToDelete = folder
                            }
                            .tint(UD.errorFg)
                            Button("Rename", systemImage: "pencil") {
                                nameFolder(folder)
                            }
                            .tint(UD.textTertiary)
                        }
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") { nameFolder(folder) }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                folderToDelete = folder
                            }
                        }
                }
                if trimmedSearch.isEmpty {
                    folderButton("No Folder", count: notes.filter { $0.folder == nil }.count, id: Self.unfiledFolderID)
                    Button("New Folder", systemImage: "folder.badge.plus") {
                        nameFolder(nil)
                    }
                    .udLinkRow()
                    .udFormRow()
                    .listRowSeparator(.hidden, edges: .bottom)
                }
            } header: {
                UDFormGap()
            }
        }
        .udFormBackground()
        .contentMargins(.bottom, ComposerButtonClearance.height, for: .scrollContent)
        .overlay {
            if !trimmedSearch.isEmpty && shown.isEmpty {
                searchEmptyState(trimmedSearch)
            }
        }
    }

    private func folderButton(_ name: String, count: Int, id: String) -> some View {
        Button {
            folderID = id
            showsFolders = false
        } label: {
            HStack(spacing: 12) {
                Text(name)
                    .font(.body)
                    .foregroundStyle(UD.textPrimary)
                Spacer(minLength: 8)
                Text("\(count)")
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(UD.textTertiary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(UD.textQuaternary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .udFormRow()
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(count) notes")
    }

    private func row(_ note: Note, isLast: Bool) -> some View {
        // The Pinned heading already says which notes are pinned.
        NoteCardLink(note: note, showsPin: false, showsDivider: !isLast)
        .swipeActions(edge: .leading) {
            Button {
                togglePin(note)
            } label: {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            .tint(UD.brand600)
        }
        .swipeActions(edge: .trailing) {
            // Not marked destructive: that role slides the row away before the person answers.
            Button {
                noteToDelete = note
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(UD.errorFg)
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
                noteToDelete = note
            }
        }
    }

    /// Shows an alert while `value` is set, and clears it when the alert closes.
    private func isPresenting<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
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
        lastDeletedNote.wrappedValue = DeletedNote(note)
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

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if showsFolders {
            // Folders reads like a screen one step in from Notes, so it gets a way back.
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showsFolders = false
                } label: {
                    Label("Notes", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityHint("Shows the notes list")
            }
        } else {
            UDOverlineToolbarItem(text: "\(visible.count) \(visible.count == 1 ? "note" : "notes")")
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
                        ? "line.3.horizontal.decrease"
                        : "line.3.horizontal.decrease.circle.fill")
                }
                .tint(UD.textPrimary)
                .accessibilityLabel("Sort and filter")
            }
            .udPlain()
            ToolbarItem(placement: .topBarTrailing) {
                Button("Folders", systemImage: "folder") {
                    showsFolders = true
                }
                .tint(UD.textPrimary)
            }
            .udPlain()
        }
    }
}

/// A note as a plain row in a list, opening the editor on tap.
struct NoteCardLink: View {
    let note: Note
    var showsPin = true
    /// Draws the hairline under the row. Off for the last row of a group.
    var showsDivider = true

    var body: some View {
        NoteRow(note: note, showsPin: showsPin)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                if showsDivider { UDDivider() }
            }
            // The link sits behind the row, so the list doesn't add its own chevron.
            .background {
                NavigationLink {
                    NoteEditorView(note: note)
                } label: {
                    EmptyView()
                }
                .opacity(0)
            }
            .udPlainRow()
    }
}

struct NoteRow: View {
    let note: Note
    var showsPin = true

    /// Edit date, then the folder name when the note is in one.
    private var meta: String {
        let date = note.updatedAt.formatted(date: .abbreviated, time: .omitted)
        return note.folder.map { "\(date) · \($0.name)" } ?? date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if showsPin && note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(UD.textTertiary)
                        .accessibilityLabel("Pinned")
                }
                Text(note.displayTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(UD.textPrimary)
                    .lineLimit(1)
            }
            if !note.preview.isEmpty {
                Text(note.preview)
                    .font(.subheadline)
                    .foregroundStyle(UD.textSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Text(meta)
                    .accessibilityLabel(note.folder.map { "\(note.updatedAt.formatted(date: .abbreviated, time: .omitted)), folder \($0.name)" } ?? meta)
                if !(note.images ?? []).isEmpty {
                    Image(systemName: "photo")
                        .accessibilityLabel("Has images")
                }
                if note.hasItemLinks {
                    Image(systemName: "paperclip")
                        .accessibilityLabel("Attached to an event or task")
                }
            }
            .font(.caption)
            .foregroundStyle(UD.textTertiary)
            .padding(.top, 2)
        }
    }
}
