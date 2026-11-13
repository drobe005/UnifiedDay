#if os(macOS)
import SwiftData
import SwiftUI

/// Notes on the Mac: the list on the left, the open note on the right.
struct MacNotesView: View {
    typealias Sort = NotesListView.Sort
    typealias Filter = NotesListView.Filter

    @Environment(EventKitService.self) private var eventKit
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedNoteID: PersistentIdentifier?

    @Query private var notes: [Note]
    @Query(sort: \NoteFolder.name) private var folders: [NoteFolder]
    // Same settings as the iPhone screen. The composer reads the folder so new
    // notes land in the one being viewed.
    @AppStorage(NotesListView.folderKey) private var folderID = ""
    @AppStorage("notesSort") private var sort = Sort.edited
    @AppStorage("notesFilter") private var filter = Filter.all
    @State private var editingFolder: NoteFolder?
    @State private var isNamingFolder = false
    @State private var folderName = ""

    private var currentFolder: NoteFolder? {
        folders.first { $0.uuid.uuidString == folderID }
    }

    private var title: String {
        if folderID == NotesListView.unfiledFolderID { return "No Folder" }
        return currentFolder?.name ?? "Notes"
    }

    private var selectedNote: Note? {
        notes.first { $0.persistentModelID == selectedNoteID }
    }

    private var visible: [Note] {
        notes
            .filter { note in
                switch folderID {
                case "": true
                case NotesListView.unfiledFolderID: note.folder == nil
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
            .sorted { a, b in
                switch sort {
                case .edited: a.updatedAt > b.updatedAt
                case .created: a.createdAt > b.createdAt
                case .title: a.displayTitle.localizedStandardCompare(b.displayTitle) == .orderedAscending
                }
            }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                MacScreenHeader(title: title) {
                    folderMenu
                    sortMenu
                    MacNewButton()
                }
                list
            }
            .frame(width: 360)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .trailing) {
                Rectangle().fill(UD.borderSecondary).frame(width: 1)
            }

            Group {
                if let note = selectedNote {
                    NoteEditorView(note: note) { selectedNoteID = nil }
                        .id(note.persistentModelID)
                        .padding(.top, MacLayout.titleBarHeight)
                        .background(UD.bgCard)
                } else {
                    UDEmptyState(
                        icon: "note.text",
                        title: notes.isEmpty ? "No notes yet" : "No note selected",
                        message: notes.isEmpty ? "Press Cmd N to write one." : "Choose a note on the left to read or edit it."
                    )
                    .frame(maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert(editingFolder == nil ? "New Folder" : "Rename Folder", isPresented: $isNamingFolder) {
            TextField("Name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveFolderName() }
        } message: {
            Text("Deleting a folder later keeps its notes.")
        }
        .onChange(of: folders) {
            // The folder being viewed was deleted, here or on another device.
            if !folderID.isEmpty, folderID != NotesListView.unfiledFolderID, currentFolder == nil {
                folderID = ""
            }
        }
    }

    // MARK: - List

    private var list: some View {
        let pinned = visible.filter(\.isPinned)
        let others = visible.filter { !$0.isPinned }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if !pinned.isEmpty {
                    UDListHeader(title: "Pinned", count: pinned.count)
                    ForEach(pinned, content: row)
                }
                if !others.isEmpty {
                    if !pinned.isEmpty {
                        UDListHeader(title: "Notes", count: others.count)
                            .padding(.top, 8)
                    }
                    ForEach(others, content: row)
                }
            }
            .padding(.horizontal, MacLayout.contentPadding)
            .padding(.bottom, 16)
        }
        .overlay {
            if !notes.isEmpty && visible.isEmpty {
                UDEmptyState(icon: "folder", title: "No notes here", message: "Try another folder or filter.")
            }
        }
    }

    private func row(_ note: Note) -> some View {
        let isSelected = note.persistentModelID == selectedNoteID
        return Button {
            selectedNoteID = note.persistentModelID
        } label: {
            NoteRow(note: note)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(isSelected ? UD.brand50 : UD.bgCard, in: RoundedRectangle(cornerRadius: UD.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: UD.cardRadius, style: .continuous)
                        .strokeBorder(isSelected ? UD.brand600 : UD.borderSecondary, lineWidth: isSelected ? 2 : 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
            .contextMenu {
                Button(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin") {
                    note.isPinned.toggle()
                    save()
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

    // MARK: - Menus

    private var folderMenu: some View {
        Menu {
            Picker("Folder", selection: $folderID) {
                Label("All Notes", systemImage: "tray.full").tag("")
                ForEach(folders) { folder in
                    Label(folder.name, systemImage: "folder").tag(folder.uuid.uuidString)
                }
                Label("No Folder", systemImage: "tray").tag(NotesListView.unfiledFolderID)
            }
            .pickerStyle(.inline)
            Divider()
            Button("New Folder...", systemImage: "folder.badge.plus") { nameFolder(nil) }
            if let currentFolder {
                Button("Rename \"\(currentFolder.name)\"...", systemImage: "pencil") { nameFolder(currentFolder) }
                Button("Delete \"\(currentFolder.name)\"", systemImage: "trash", role: .destructive) {
                    modelContext.delete(currentFolder)
                    save()
                }
            }
        } label: {
            Image(systemName: "folder")
                .frame(width: 18, height: 18)
        }
        .menuStyle(.button)
        .buttonStyle(UDSmallButtonStyle())
        .fixedSize()
        .help("Folders")
        .accessibilityLabel("Folders")
    }

    private var sortMenu: some View {
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
                .frame(width: 18, height: 18)
        }
        .menuStyle(.button)
        .buttonStyle(UDSmallButtonStyle())
        .fixedSize()
        .help("Sort and filter")
        .accessibilityLabel("Sort and filter")
    }

    // MARK: - Actions

    private func save() {
        modelContext.saveNotes(reportingTo: eventKit)
    }

    private func move(_ note: Note, to folder: NoteFolder?) {
        note.folder = folder
        save()
    }

    private func delete(_ note: Note) {
        if note.persistentModelID == selectedNoteID {
            selectedNoteID = nil
        }
        modelContext.delete(note)
        save()
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
        save()
    }
}
#endif
