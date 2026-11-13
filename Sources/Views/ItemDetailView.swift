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
    @State private var choosingSaveSpan = false
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
                        UDFormFooter(text: "This \(isEvent ? "calendar" : "list") is read-only, so this item can't be changed here.")
                    }
                }
                .udFormRow()

                AttachedNotesSection(
                    item: item,
                    onNewNote: { showingNewNote = true },
                    onAttachExisting: { showingNotePicker = true }
                )

                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(UD.errorFg)
                    }
                    .listRowBackground(UD.errorBg)
                }

                if !item.isReadOnly {
                    // In the footer, not a row, so the form's rounded row shape doesn't clip it.
                    Section {
                    } footer: {
                        Button("Delete \(isEvent ? "Event" : "Reminder")", role: .destructive) {
                            confirmingDelete = true
                        }
                        .buttonStyle(UDDestructiveButtonStyle())
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    }
                }
            }
            .udFormBackground()
            .tint(UD.brand600)
            .navigationTitle(isEvent ? "Event" : "Reminder")
            .udInlineTitle()
            .toolbar { toolbar }
            .sheet(isPresented: $showingNewNote) {
                ComposerView(initialKind: .note, attachingTo: item)
            }
            .sheet(isPresented: $showingNotePicker) {
                NotePickerView(item: item)
            }
            .confirmationDialog(
                "Save changes to this repeating event?",
                isPresented: $choosingSaveSpan,
                titleVisibility: .visible
            ) {
                Button("Save for This Event Only") { save() }
                Button("Save for All Future Events") { save(includingFuture: true) }
            } message: {
                Text("Changes will also show in Apple Calendar.")
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
            TextField("Add a title", text: $title)
                .foregroundStyle(UD.textPrimary)
        } header: {
            UDFormHeader(title: "Title")
        }
        .udFormRow()

        if isEvent {
            Section {
                Toggle("All day", isOn: $isAllDay)
                DatePicker("Starts", selection: $start, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                DatePicker("Ends", selection: $end, in: start..., displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                RepeatPicker(selection: $repeatOption)
            } footer: {
                if repeatOption != item.repeatOption && item.repeatOption != .never {
                    UDFormFooter(text: "Changing the repeat updates this and every later event in the series.")
                }
            }
            .udFormRow()
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
            .udFormRow()
        }

        Section {
            TextField("Optional", text: $notes, axis: .vertical)
                .lineLimit(4...10)
        } header: {
            UDFormHeader(title: "Apple notes")
        }
        .udFormRow()
    }

    @ViewBuilder
    private var readOnlyContent: some View {
        Section {
            Text(item.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(UD.textPrimary)
            if let when = whenLabel {
                LabeledContent(isEvent ? "When" : "Due", value: when)
            }
            if item.repeatOption != .never {
                LabeledContent("Repeat", value: item.repeatOption.label)
            }
        }
        .udFormRow()
        if let itemNotes = item.notes, !itemNotes.isEmpty {
            Section {
                Text(itemNotes)
                    .foregroundStyle(UD.textSecondary)
            } header: {
                UDFormHeader(title: "Apple notes")
            }
            .udFormRow()
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
                UDToolbarConfirmButton(title: "Done") { dismiss() }
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                UDToolbarConfirmButton { saveTapped() }
                    .disabled(trimmedTitle.isEmpty)
            }
        }
    }

    // MARK: - Actions

    /// A repeating event asks whether the edit is for this occurrence or every later one,
    /// like Apple Calendar. Changing the repeat always changes every later one, so it
    /// doesn't ask then.
    private func saveTapped() {
        if item.isRepeatingEvent && repeatOption == item.repeatOption {
            choosingSaveSpan = true
        } else {
            save()
        }
    }

    private func save(includingFuture: Bool = false) {
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
                repeatOption: repeatOption,
                includingFuture: includingFuture
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
