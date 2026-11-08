import PhotosUI
import SwiftData
import SwiftUI

/// Edits one note. Changes save as you type; Save also saves and closes the note.
struct NoteEditorView: View {
    @Environment(EventKitService.self) private var eventKit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.composerButtonHidden) private var composerButtonHidden

    let note: Note

    @State private var showingItemPicker = false
    @State private var viewingImage: NoteImage?
    /// Opened from an attached row. The sheet lives here because a sheet on a
    /// Form row often never appears.
    @State private var openingItem: TimelineItem?
    @State private var confirmingDelete = false
    /// Deleting waits until the screen closes, so it never shows a deleted note.
    @State private var deleteOnClose = false

    var body: some View {
        Form {
            Section {
                TextField("Title", text: edit(\.title))
                    .font(.headline)
                if #available(iOS 26.0, *) {
                    RichNoteEditor(note: note)
                } else {
                    TextField("Write something", text: edit(\.text), axis: .vertical)
                        .lineLimit(8...)
                }
            } footer: {
                Text("Saved in UnifiedDay and your iCloud. Not visible in Apple's apps.")
            }

            NoteImagesSection(note: note, viewing: $viewingImage)

            Section {
                NoteFolderPicker(selection: folderSelection)
            }

            Section("Attached to") {
                ForEach(note.attachedLinks) { link in
                    AttachedItemRow(link: link) { openingItem = $0 }
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
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: note.shareText)
                    .disabled(note.shareText.isEmpty)
                Button {
                    note.isPinned.toggle()
                } label: {
                    Image(systemName: note.isPinned ? "pin.slash" : "pin")
                }
                .accessibilityLabel(note.isPinned ? "Unpin" : "Pin")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    modelContext.saveNotes(reportingTo: eventKit)
                    dismiss()
                }
            }
        }
        .onAppear { composerButtonHidden.wrappedValue = true }
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
        .sheet(item: $openingItem) { item in
            ItemDetailView(item: item) {}
        }
        .sheet(item: $viewingImage) { image in
            NoteImageViewer(image: image) {
                NoteImagesSection.delete(image, from: note, in: modelContext, reportingTo: eventKit)
            }
        }
        .onDisappear {
            composerButtonHidden.wrappedValue = false
            if deleteOnClose {
                modelContext.delete(note)
            }
            modelContext.saveNotes(reportingTo: eventKit)
        }
    }

    private var folderSelection: Binding<NoteFolder?> {
        Binding {
            note.folder
        } set: { folder in
            note.folder = folder
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

/// The note's body with formatting. Buttons above the keyboard apply bold, italic,
/// underline, strikethrough, headings, bullets, and checklists.
@available(iOS 26.0, *)
struct RichNoteEditor: View {
    let note: Note

    @State private var text: AttributedString
    @State private var selection = AttributedTextSelection()
    @FocusState private var isFocused: Bool

    init(note: Note) {
        self.note = note
        _text = State(initialValue: RichText.decode(note.richText, plainText: note.text))
    }

    private var current: RichTextStyle {
        let styles = selection.attributes(in: text).map(RichTextStyle.init)
        guard let first = styles.first else { return RichTextStyle() }
        return RichTextStyle(
            bold: styles.allSatisfy(\.bold) && first.bold,
            italic: styles.allSatisfy(\.italic) && first.italic,
            underline: styles.allSatisfy(\.underline) && first.underline,
            strikethrough: styles.allSatisfy(\.strikethrough) && first.strikethrough,
            heading: styles.allSatisfy(\.heading) && first.heading
        )
    }

    var body: some View {
        TextEditor(text: $text, selection: $selection)
            .focused($isFocused)
            .frame(minHeight: 200)
            .overlay(alignment: .topLeading) {
                if text.characters.isEmpty {
                    Text("Write something")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .toolbar {
                if isFocused {
                    // One item, so every button fits instead of spilling into a "more" menu.
                    ToolbarItem(placement: .keyboard) {
                        HStack(spacing: 20) {
                            formatButton("Bold", "bold", on: current.bold) { $0.bold.toggle() }
                            formatButton("Italic", "italic", on: current.italic) { $0.italic.toggle() }
                            formatButton("Underline", "underline", on: current.underline) { $0.underline.toggle() }
                            formatButton("Strikethrough", "strikethrough", on: current.strikethrough) { $0.strikethrough.toggle() }
                            formatButton("Heading", "textformat.size.larger", on: current.heading) { $0.heading.toggle() }
                            Button("Bulleted list", systemImage: "list.bullet", action: toggleBullet)
                                .labelStyle(.iconOnly)
                            Button("Checklist", systemImage: "checklist", action: toggleChecklist)
                                .labelStyle(.iconOnly)
                                .accessibilityHint("Adds a checkbox, or checks and unchecks it")
                            Button("Done", systemImage: "keyboard.chevron.compact.down") { isFocused = false }
                                .labelStyle(.iconOnly)
                        }
                    }
                }
            }
            .onChange(of: text) { old, new in
                if new.characters.count == old.characters.count + 1 {
                    continueList()
                }
                save()
            }
    }

    private static let bullet = "• "
    private static let openBox = "☐ "
    private static let checkedBox = "☑ "
    private static let listPrefixes = [bullet, openBox, checkedBox]

    /// After Return on a bullet or checklist line, starts the next line the same way,
    /// with an unchecked box for checklists. Return on an empty one removes it and
    /// ends the list, as in Apple Notes.
    private func continueList() {
        guard case .insertionPoint(let point) = selection.indices(in: text),
              point > text.startIndex else { return }
        let newline = text.characters.index(before: point)
        guard text.characters[newline] == "\n" else { return }

        let start = Self.lineStart(in: text, at: newline)
        let line = String(text.characters[start..<newline])
        guard let prefix = Self.listPrefixes.first(where: line.hasPrefix) else { return }

        let startOffset = text.characters.distance(from: text.startIndex, to: start)
        if line == prefix {
            text.removeSubrange(start..<point)
            placeCursor(atOffset: startOffset)
        } else {
            let next = prefix == Self.bullet ? Self.bullet : Self.openBox
            let pointOffset = text.characters.distance(from: text.startIndex, to: point)
            text.insert(AttributedString(next, attributes: RichTextStyle().attributes), at: point)
            placeCursor(atOffset: pointOffset + next.count)
        }
    }

    /// Puts the cursor after a list marker the app just added. Left alone, the
    /// cursor stays in front of inserted text and typing would land before the marker.
    private func placeCursor(atOffset offset: Int) {
        let clamped = min(max(offset, 0), text.characters.count)
        selection = AttributedTextSelection(insertionPoint: text.characters.index(text.startIndex, offsetBy: clamped))
    }

    /// The start of the line that holds `index`.
    private static func lineStart(in text: AttributedString, at index: AttributedString.Index) -> AttributedString.Index {
        var start = index
        while start > text.startIndex {
            let previous = text.characters.index(before: start)
            if text.characters[previous] == "\n" { break }
            start = previous
        }
        return start
    }

    /// Swaps the list marker at the start of the cursor's line: `change` gets the
    /// current marker (nil for none) and returns the new one (nil removes it).
    private func changeLinePrefix(_ change: (String?) -> String?) {
        let index: AttributedString.Index
        let isCursor: Bool
        switch selection.indices(in: text) {
        case .insertionPoint(let point):
            index = point
            isCursor = true
        case .ranges(let ranges):
            index = ranges.ranges.first?.lowerBound ?? text.startIndex
            isCursor = false
        }
        let start = Self.lineStart(in: text, at: index)
        let startOffset = text.characters.distance(from: text.startIndex, to: start)
        let cursorOffset = text.characters.distance(from: text.startIndex, to: index)
        let current = Self.listPrefixes.first { text.characters[start...].starts(with: $0) }
        let replacement = change(current)

        text.transform(updating: &selection) { text in
            if let current {
                let end = text.characters.index(start, offsetBy: current.count)
                text.removeSubrange(start..<end)
            }
            if let replacement {
                text.insert(AttributedString(replacement, attributes: RichTextStyle().attributes), at: start)
            }
        }

        // Keep the cursor on the same spot in the line's text, never in front of the marker.
        guard isCursor else { return }
        let removed = current?.count ?? 0
        let added = replacement?.count ?? 0
        let textOffset = max(cursorOffset - startOffset - removed, 0)
        placeCursor(atOffset: startOffset + added + textOffset)
    }

    private func formatButton(
        _ title: String,
        _ symbol: String,
        on: Bool,
        change: @escaping (inout RichTextStyle) -> Void
    ) -> some View {
        Button {
            // Apply one target style to the whole selection, so mixed text turns all on.
            var target = current
            change(&target)
            text.transformAttributes(in: &selection) { container in
                var style = RichTextStyle(container)
                style.bold = target.bold
                style.italic = target.italic
                style.underline = target.underline
                style.strikethrough = target.strikethrough
                style.heading = target.heading
                style.apply(to: &container)
            }
        } label: {
            Image(systemName: symbol)
                .foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Adds or removes a bullet at the start of the cursor's line. A checklist line
    /// turns into a bullet.
    private func toggleBullet() {
        changeLinePrefix { $0 == Self.bullet ? nil : Self.bullet }
    }

    /// Adds a checkbox to the cursor's line, or checks and unchecks the one there.
    private func toggleChecklist() {
        changeLinePrefix { $0 == Self.openBox ? Self.checkedBox : Self.openBox }
    }

    private func save() {
        let plain = String(text.characters)
        let data = RichText.encode(text)
        guard data != note.richText else { return }
        // Opening an older note converts it once; only real edits, formatting included, change the date.
        let unformatted = RichText.encode(RichText.decode(nil, plainText: note.text))
        if note.richText != nil || data != unformatted {
            note.updatedAt = .now
        }
        note.text = plain
        note.richText = data
    }
}

/// An event or reminder attached to a note. Tap to open it, swipe to detach it.
struct AttachedItemRow: View {
    @Environment(EventKitService.self) private var eventKit
    @Environment(\.modelContext) private var modelContext

    let link: NoteLink
    let onOpen: (TimelineItem) -> Void

    @State private var item: TimelineItem?

    var body: some View {
        // A tap gesture, not a Button: a plain Button in this Form row didn't respond.
        VStack(alignment: .leading, spacing: 2) {
            Text(item?.title ?? link.title)
                .foregroundStyle(item == nil ? .secondary : .primary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if let item { onOpen(item) }
        }
        .accessibilityAddTraits(item == nil ? [] : .isButton)
        .accessibilityHint(item == nil ? "" : "Opens details")
        .swipeActions(edge: .trailing) {
            Button("Detach", role: .destructive) {
                modelContext.delete(link)
                modelContext.saveNotes(reportingTo: eventKit)
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

/// Folder choice for a note, with a way to make a new folder on the spot.
struct NoteFolderPicker: View {
    @Environment(EventKitService.self) private var eventKit
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NoteFolder.name) private var folders: [NoteFolder]

    @Binding var selection: NoteFolder?

    @State private var isNaming = false
    @State private var name = ""

    var body: some View {
        Picker("Folder", selection: $selection) {
            Text("None").tag(NoteFolder?.none)
            ForEach(folders) { folder in
                Text(folder.name).tag(Optional(folder))
            }
        }
        Button("New Folder", systemImage: "folder.badge.plus") {
            name = ""
            isNaming = true
        }
        .alert("New Folder", isPresented: $isNaming) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Create") { create() }
        } message: {
            Text("The note moves into the new folder.")
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let folder = NoteFolder(name: trimmed)
        modelContext.insert(folder)
        modelContext.saveNotes(reportingTo: eventKit)
        selection = folder
    }
}

/// An image from the clipboard, for the Paste button.
struct PastedImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { PastedImage(data: $0) }
    }
}

/// A note's images, with buttons to add a photo or paste an image. Images sit
/// under the text, not inside it.
struct NoteImagesSection: View {
    @Environment(EventKitService.self) private var eventKit
    @Environment(\.modelContext) private var modelContext

    let note: Note
    /// The image open full screen. The editor screen shows it, since a sheet
    /// attached inside a form section doesn't open reliably.
    @Binding var viewing: NoteImage?

    @State private var pickedPhotos: [PhotosPickerItem] = []

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 8)]

    var body: some View {
        Section("Images") {
            let images = note.sortedImages
            if !images.isEmpty {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(images) { image in
                        Button {
                            viewing = image
                        } label: {
                            NoteImageThumbnail(image: image)
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        // Borderless, so each thumbnail gets its own tap inside the form row.
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Image")
                        .accessibilityHint("Opens the image")
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(image) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            PhotosPicker(selection: $pickedPhotos, maxSelectionCount: 10, matching: .images) {
                Label("Add Photos", systemImage: "photo.on.rectangle")
            }
            PasteButton(payloadType: PastedImage.self) { pasted in
                add(pasted.map(\.data))
            }
            .labelStyle(.titleAndIcon)
        }
        .onChange(of: pickedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var loaded: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        loaded.append(data)
                    }
                }
                add(loaded)
                pickedPhotos = []
            }
        }
    }

    private func add(_ items: [Data]) {
        let prepared = items.compactMap(NoteImage.preparedData(from:))
        guard !prepared.isEmpty else {
            if !items.isEmpty { eventKit.lastError = "That image couldn't be added." }
            return
        }
        for data in prepared {
            let image = NoteImage(data: data)
            modelContext.insert(image)
            image.note = note
        }
        note.updatedAt = .now
        modelContext.saveNotes(reportingTo: eventKit)
    }

    private func delete(_ image: NoteImage) {
        Self.delete(image, from: note, in: modelContext, reportingTo: eventKit)
    }

    static func delete(_ image: NoteImage, from note: Note, in context: ModelContext, reportingTo eventKit: EventKitService) {
        context.delete(image)
        note.updatedAt = .now
        context.saveNotes(reportingTo: eventKit)
    }
}

/// A square preview of a note image. Shrinks the image once, not on every redraw.
struct NoteImageThumbnail: View {
    let image: NoteImage

    @State private var preview: UIImage?

    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .task(id: image.persistentModelID) {
                preview = image.data
                    .flatMap(UIImage.init(data:))?
                    .preparingThumbnail(of: CGSize(width: 240, height: 240))
            }
    }
}

/// One note image, full screen.
struct NoteImageViewer: View {
    @Environment(\.dismiss) private var dismiss

    let image: NoteImage
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if let data = image.data, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("Image")
                } else {
                    ContentUnavailableView("Image not available", systemImage: "photo")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
        }
    }
}
