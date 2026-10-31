import SwiftUI

/// One composer for both types. Segmented control picks event vs reminder.
/// Design target: under 10 seconds from open to saved.
struct ComposerView: View {
    @Environment(EventKitService.self) private var eventKit
    @Environment(\.dismiss) private var dismiss

    enum DraftKind { case event, reminder }

    @State private var kind: DraftKind = .reminder
    @State private var title = ""
    @State private var date = Date.now
    @State private var includeTime = true
    @State private var notes = ""
    @State private var selectedCalendarID: String?
    @State private var selectedListID: String?
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    Text("Reminder").tag(DraftKind.reminder)
                    Text("Event").tag(DraftKind.event)
                }
                .pickerStyle(.segmented)

                Section {
                    TextField("Title", text: $title)
                        .focused($titleFocused)
                }

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

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(kind == .event ? "New Event" : "New Reminder")
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
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if kind == .event {
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
