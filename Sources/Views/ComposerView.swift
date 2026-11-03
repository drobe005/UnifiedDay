import SwiftData
import SwiftUI

/// One composer for all types. Segmented control picks reminder, event, or note.
/// Design target: under 10 seconds from open to saved.
struct ComposerView: View {
    @Environment(EventKitService.self) private var eventKit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    enum DraftKind { case event, reminder, note }

    @State private var kind: DraftKind
    @State private var title = ""
    @State private var date: Date
    @State private var includeTime = true
    @State private var notes = ""
    @State private var selectedCalendarID: String?
    @State private var selectedListID: String?
    @State private var attachments: [TimelineItem] = []
    @State private var showingItemPicker = false
    @State private var repeatOption = RepeatOption.never
    @State private var folderID: UUID?
    @Query(sort: \NoteFolder.name) private var folders: [NoteFolder]
    @AppStorage(NotesListView.folderKey) private var viewedFolderID = ""
    @FocusState private var titleFocused: Bool

    /// When set, the composer writes a note for this item and hides the type picker.
    private let attachedItem: TimelineItem?

    init(initialDate: Date = .now, initialKind: DraftKind = .reminder, attachingTo item: TimelineItem? = nil) {
        _date = State(initialValue: initialDate)
        _kind = State(initialValue: initialKind)
        attachedItem = item
    }

    private var navigationTitle: String {
        switch kind {
        case .event: "New Event"
        case .reminder: "New Reminder"
        case .note: "New Note"
        }
    }

    private var canSave: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespaces).isEmpty
        return hasTitle || (kind == .note && !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                if attachedItem == nil {
                    Picker("Type", selection: $kind) {
                        Text("Reminder").tag(DraftKind.reminder)
                        Text("Event").tag(DraftKind.event)
                        Text("Note").tag(DraftKind.note)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("Title", text: $title)
                        .focused($titleFocused)
                }

                if kind == .note {
                    Section {
                        TextField("Write something", text: $notes, axis: .vertical)
                            .lineLimit(6...)
                    } footer: {
                        Text("Saved in UnifiedDay and your iCloud. Not visible in Apple's apps.")
                    }

                    if !folders.isEmpty {
                        Section {
                            Picker("Folder", selection: $folderID) {
                                Text("None").tag(UUID?.none)
                                ForEach(folders) { folder in
                                    Text(folder.name).tag(Optional(folder.uuid))
                                }
                            }
                        }
                    }

                    Section("Attached to") {
                        if let attachedItem {
                            attachmentRow(attachedItem)
                        }
                        ForEach(attachments) { item in
                            attachmentRow(item)
                                .swipeActions(edge: .trailing) {
                                    Button("Remove", role: .destructive) {
                                        attachments.removeAll { $0.linkKey == item.linkKey }
                                    }
                                }
                        }
                        Button("Attach Events or Reminders") {
                            showingItemPicker = true
                        }
                    }
                } else {
                    Section {
                        DatePicker("Date", selection: $date, displayedComponents: includeTime ? [.date, .hourAndMinute] : [.date])
                        Toggle("Include time", isOn: $includeTime)
                        RepeatPicker(selection: $repeatOption)
                    }

                    Section {
                        if kind == .event {
                            Picker("Calendar", selection: $selectedCalendarID) {
                                ForEach(eventKit.writableEventCalendars(), id: \.calendarIdentifier) { calendar in
                                    Text(calendar.title).tag(Optional(calendar.calendarIdentifier))
                                }
                            }
                        } else {
                            Picker("List", selection: $selectedListID) {
                                ForEach(eventKit.writableReminderLists(), id: \.calendarIdentifier) { list in
                                    Text(list.title).tag(Optional(list.calendarIdentifier))
                                }
                            }
                        }
                    }

                    Section("Apple notes") {
                        TextField("Optional", text: $notes, axis: .vertical)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingItemPicker) {
                ItemPickerView(isAttached: isAttached) { items in
                    attachments += items
                }
            }
            .onAppear {
                selectedCalendarID = eventKit.preferredEventCalendar()?.calendarIdentifier
                selectedListID = eventKit.preferredReminderList()?.calendarIdentifier
                // New notes go in the folder being viewed on the Notes tab.
                folderID = folders.first { $0.uuid.uuidString == viewedFolderID }?.uuid
                titleFocused = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func isAttached(_ item: TimelineItem) -> Bool {
        item.linkKey == attachedItem?.linkKey || attachments.contains { $0.linkKey == item.linkKey }
    }

    private func attachmentRow(_ item: TimelineItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
            Text(item.scheduleLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if kind == .note {
            let note = Note(title: trimmed, text: notes)
            modelContext.insert(note)
            note.folder = folders.first { $0.uuid == folderID }
            note.attach([attachedItem].compactMap { $0 } + attachments, in: modelContext)
            modelContext.saveNotes(reportingTo: eventKit)
        } else if kind == .event {
            let calendar = eventKit.writableEventCalendars().first { $0.calendarIdentifier == selectedCalendarID }
            let start = includeTime ? date : Calendar.current.startOfDay(for: date)
            let end = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
            eventKit.createEvent(
                title: trimmed,
                start: start,
                end: end,
                isAllDay: !includeTime,
                calendar: calendar,
                notes: notes.isEmpty ? nil : notes,
                repeatOption: repeatOption
            )
        } else {
            let list = eventKit.writableReminderLists().first { $0.calendarIdentifier == selectedListID }
            eventKit.createReminder(
                title: trimmed,
                dueDate: date,
                includeTime: includeTime,
                list: list,
                notes: notes.isEmpty ? nil : notes,
                repeatOption: repeatOption
            )
        }
        dismiss()
    }
}

/// Repeat choices for events and reminders. Shows Custom only when an item
/// already repeats in a way made in Apple's apps.
struct RepeatPicker: View {
    @Binding var selection: RepeatOption

    var body: some View {
        Picker("Repeat", selection: $selection) {
            ForEach(RepeatOption.choices) { Text($0.label).tag($0) }
            if selection == .custom {
                Text(RepeatOption.custom.label).tag(RepeatOption.custom)
            }
        }
    }
}
