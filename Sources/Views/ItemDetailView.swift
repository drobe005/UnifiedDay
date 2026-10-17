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
    @State private var saveError: String?
    @State private var confirmingDelete = false

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
    }

    private var isEvent: Bool { item.kind == .event }
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
                    LabeledContent(isEvent ? "Calendar" : "List") {
                        HStack(spacing: 6) {
                            Circle().fill(item.sourceColor).frame(width: 10, height: 10)
                            Text(item.sourceName)
                        }
                    }
                } footer: {
                    if item.isReadOnly {
                        Text("This \(isEvent ? "calendar" : "list") is read-only, so this item can't be changed here.")
                    }
                }

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
            .confirmationDialog(
                "Delete this \(isEvent ? "event" : "reminder")?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { delete() }
            } message: {
                Text(isEvent ? "It will also be removed from Apple Calendar." : "It will also be removed from Apple Reminders.")
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
                }
            }
        }

        Section("Notes") {
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
        }
        if let itemNotes = item.notes, !itemNotes.isEmpty {
            Section("Notes") {
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
            saved = eventKit.updateEvent(item, title: trimmedTitle, start: eventStart, end: eventEnd, isAllDay: isAllDay, notes: notesValue)
        } else {
            saved = eventKit.updateReminder(
                item,
                title: trimmedTitle,
                dueDate: hasDueDate ? start : nil,
                includeTime: includeTime,
                notes: notesValue
            )
        }
        if saved {
            onChange()
            dismiss()
        } else {
            saveError = eventKit.lastError ?? "Couldn't save. Try again."
        }
    }

    private func delete() {
        eventKit.delete(item)
        onChange()
        dismiss()
    }
}
