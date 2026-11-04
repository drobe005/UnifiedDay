import SwiftUI

/// Detail sheet for one timeline row. Edits save straight back to EventKit.
/// Items from read-only calendars or lists show details without edit controls.
struct ItemDetailView: View {
    @Environment(EventKitService.self) private var eventKit
    @Environment(\.dismiss) private var dismiss

    let item: TimelineItem
    let onChange: () -> Void

    @State private var title: String
    @State private var notes: String
    @State private var start: Date
    @State private var end: Date
    @State private var isAllDay: Bool
    @State private var hasDueDate: Bool
    @State private var includeTime: Bool
    @State private var sourceID: String
    @State private var repeatOption: RepeatOption
    @State private var saveError: String?
    @State private var confirmingDelete = false
    @State private var showingNewNote = false
    @State private var showingNotePicker = false

    init(item: TimelineItem, onChange: @escaping () -> Void) {
        self.item = item
        self.onChange = onChange
        let start = item.startDate ?? Calendar.current.startOfDay(for: .now)
        _title = State(initialValue: item.title)
        _notes = State(initialValue: item.notes ?? "")
        _start = State(initialValue: start)
        _end = State(initialValue: item.endDate ?? start.addingTimeInterval(3600))
        _isAllDay = State(initialValue: item.isAllDay)
        _hasDueDate = State(initialValue: item.startDate != nil)
        _includeTime = State(initialValue: item.hasDueTime)
        _sourceID = State(initialValue: item.sourceID)
        _repeatOption = State(initialValue: item.repeatOption)
    }

    private var isEvent: Bool { item.kind == .event }
    private var sourceOptions: [(id: String, title: String)] {
        (isEvent ? eventKit.writableEventCalendars() : eventKit.writableReminderLists())
            .map { (id: $0.calendarIdentifier, title: $0.title) }
    }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                if item.isReadOnly {
                    readOnlyContent
                } else {
                    editableContent
                }

                Section {
                    if item.isReadOnly {
                        LabeledContent(isEvent ? "Calendar" : "List") {
                            HStack(spacing: 6) {
                                Circle().fill(item.sourceColor).frame(width: 10, height: 10)
                                Text(item.sourceName)
                            }
                        }
                    } else {
                        Picker(isEvent ? "Calendar" : "List", selection: $sourceID) {
                            ForEach(sourceOptions, id: \.id) { option in
                                Text(option.title).tag(option.id)
                            }
                        }
                    }
                } footer: {
                    if item.isReadOnly {
                        Text("This \(isEvent ? "calendar" : "list") is read-only, so this item can't be changed here.")
                    }
                }

                AttachedNotesSection(
                    item: item,
                    onNewNote: { showingNewNote = true },
                    onAttachExisting: { showingNotePicker = true }
                )

                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                if !item.isReadOnly {
                    Section {
                        Button("Delete \(isEvent ? "Event" : "Reminder")", role: .destructive) {
                            confirmingDelete = true
                        }
                    }
                }
            }
            .navigationTitle(isEvent ? "Event" : "Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $showingNewNote) {
                ComposerView(initialKind: .note, attachingTo: item)
            }
            .sheet(isPresented: $showingNotePicker) {
                NotePickerView(item: item)
            }
            .confirmationDialog(
                "Delete this \(isEvent ? "event" : "reminder")?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                if item.isRepeatingEvent {
                    Button("Delete This Event Only", role: .destructive) { delete() }
                    Button("Delete All Future Events", role: .destructive) { delete(includingFuture: true) }
                } else {
                    Button("Delete", role: .destructive) { delete() }
                }
            } message: {
                if item.isRepeatingEvent {
                    Text("This is a repeating event. It will also be removed from Apple Calendar.")
                } else {
                    Text(isEvent ? "It will also be removed from Apple Calendar." : "It will also be removed from Apple Reminders.")
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var editableContent: some View {
        Section {
            TextField("Title", text: $title)
        }

        if isEvent {
            Section {
                Toggle("All day", isOn: $isAllDay)
                DatePicker("Starts", selection: $start, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                DatePicker("Ends", selection: $end, in: start..., displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                RepeatPicker(selection: $repeatOption)
            } footer: {
                if repeatOption != item.repeatOption && item.repeatOption != .never {
                    Text("Changing the repeat updates this and every later event in the series.")
                }
            }
            .onChange(of: start) { oldStart, newStart in
                // Keep the duration when the start moves, like Apple Calendar does.
                end = newStart.addingTimeInterval(max(end.timeIntervalSince(oldStart), 0))
            }
        } else {
            Section {
                Toggle("Due date", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Due", selection: $start, displayedComponents: includeTime ? [.date, .hourAndMinute] : [.date])
                    Toggle("Include time", isOn: $includeTime)
                    RepeatPicker(selection: $repeatOption)
                }
            }
        }

        Section("Apple notes") {
            TextField("Optional", text: $notes, axis: .vertical)
                .lineLimit(3...10)
        }
    }

    @ViewBuilder
    private var readOnlyContent: some View {
        Section {
            Text(item.title).font(.headline)
            if let when = whenLabel {
                LabeledContent(isEvent ? "When" : "Due", value: when)
            }
            if item.repeatOption != .never {
                LabeledContent("Repeat", value: item.repeatOption.label)
            }
        }
        if let itemNotes = item.notes, !itemNotes.isEmpty {
            Section("Apple notes") {
                Text(itemNotes)
            }
        }
    }

    private var whenLabel: String? {
        guard let startDate = item.startDate else { return nil }
        if item.isAllDay || !item.hasDueTime {
            return startDate.formatted(date: .abbreviated, time: .omitted)
        }
        guard let endDate = item.endDate else {
            return startDate.formatted(date: .abbreviated, time: .shortened)
        }
        return "\(startDate.formatted(date: .abbreviated, time: .shortened)) to \(endDate.formatted(date: .omitted, time: .shortened))"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if item.isReadOnly {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(trimmedTitle.isEmpty)
            }
        }
    }

    // MARK: - Actions

    private func save() {
        let notesValue = notes.isEmpty ? nil : notes
        let saved: Bool
        if isEvent {
            let calendar = Calendar.current
            let eventStart = isAllDay ? calendar.startOfDay(for: start) : start
            let eventEnd = isAllDay ? calendar.startOfDay(for: end) : end
            saved = eventKit.updateEvent(
                item,
                title: trimmedTitle,
                start: eventStart,
                end: eventEnd,
                isAllDay: isAllDay,
                calendarID: sourceID,
                notes: notesValue,
                repeatOption: repeatOption
            )
        } else {
            saved = eventKit.updateReminder(
                item,
                title: trimmedTitle,
                dueDate: hasDueDate ? start : nil,
                includeTime: includeTime,
                listID: sourceID,
                notes: notesValue,
                repeatOption: repeatOption
            )
        }
        if saved {
            onChange()
            dismiss()
        } else {
            saveError = eventKit.lastError ?? "Couldn't save. Try again."
        }
    }

    private func delete(includingFuture: Bool = false) {
        eventKit.delete(item, includingFuture: includingFuture)
        onChange()
        dismiss()
    }
}
