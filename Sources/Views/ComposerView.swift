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
                } else {
                    Section {
                        DatePicker("Date", selection: $date, displayedComponents: includeTime ? [.date, .hourAndMinute] : [.date])
                        Toggle("Include time", isOn: $includeTime)
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
            .onAppear {
                selectedCalendarID = eventKit.preferredEventCalendar()?.calendarIdentifier
                selectedListID = eventKit.preferredReminderList()?.calendarIdentifier
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

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if kind == .note {
            let note = Note(title: trimmed, text: notes)
            modelContext.insert(note)
            if let attachedItem {
                let link = NoteLink(item: attachedItem)
                modelContext.insert(link)
                link.note = note
            }
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
                notes: notes.isEmpty ? nil : notes
            )
        } else {
            let list = eventKit.writableReminderLists().first { $0.calendarIdentifier == selectedListID }
            eventKit.createReminder(
                title: trimmed,
                dueDate: date,
                includeTime: includeTime,
                list: list,
                notes: notes.isEmpty ? nil : notes
            )
        }
        dismiss()
    }
}
