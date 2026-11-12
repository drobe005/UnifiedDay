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
    @State private var folder: NoteFolder?
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
                    // Sits on the background, not in a card, like the Figma design.
                    Section {
                        Picker("Type", selection: $kind) {
                            Text("Reminder").tag(DraftKind.reminder)
                            Text("Event").tag(DraftKind.event)
                            Text("Note").tag(DraftKind.note)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }

                Section {
                    TextField("Add a title", text: $title)
                        .font(kind == .note ? .title3.weight(.bold) : .body)
                        .foregroundStyle(UD.textPrimary)
                        .focused($titleFocused)
                    if kind != .note, let found = TypedDate.find(in: title) {
                        Button {
                            useTypedDate(found)
                        } label: {
                            Label("Set date: \(found.label)", systemImage: "calendar.badge.plus")
                                .foregroundStyle(UD.brand700)
                        }
                    }
                } header: {
                    UDFormHeader(title: "Title")
                }
                .udFormRow()

                if kind == .note {
                    Section {
                        TextField("Write something", text: $notes, axis: .vertical)
                            .lineLimit(6...)
                    } footer: {
                        Label("Saved in UnifiedDay and your iCloud. Not visible in Apple's apps.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(UD.textTertiary)
                    }
                    .udFormRow()

                    Section {
                        NoteFolderPicker(selection: $folder)
                    }
                    .udFormRow()

                    Section {
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
                        Button("Attach Events or Reminders", systemImage: "plus") {
                            showingItemPicker = true
                        }
                    } header: {
                        UDFormHeader(title: "Attached to")
                    }
                    .udFormRow()
                } else {
                    Section {
                        DatePicker("Date", selection: $date, displayedComponents: includeTime ? [.date, .hourAndMinute] : [.date])
                        Toggle("Include time", isOn: $includeTime)
                        RepeatPicker(selection: $repeatOption)
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
                    .udFormRow()

                    Section {
                        TextField("Optional", text: $notes, axis: .vertical)
                            .lineLimit(4...)
                    } header: {
                        UDFormHeader(title: "Apple notes")
                    }
                    .udFormRow()
                }
            }
            .udFormBackground()
            .tint(UD.brand600)
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
                folder = folders.first { $0.uuid.uuidString == viewedFolderID }
                titleFocused = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    UDToolbarConfirmButton { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    /// Moves a date typed in the title into the date fields, and takes it out of the title.
    private func useTypedDate(_ found: TypedDate) {
        date = found.date
        includeTime = found.hasTime
        title = found.remainingTitle
    }

    private func isAttached(_ item: TimelineItem) -> Bool {
        item.linkKey == attachedItem?.linkKey || attachments.contains { $0.linkKey == item.linkKey }
    }

    private func attachmentRow(_ item: TimelineItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind == .event ? "calendar" : "checklist")
                .foregroundStyle(UD.textTertiary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(UD.textPrimary)
                Text(item.scheduleLabel)
                    .font(.subheadline)
                    .foregroundStyle(UD.textTertiary)
            }
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if kind == .note {
            let note = Note(title: trimmed, text: notes)
            modelContext.insert(note)
            note.folder = folder
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

/// A date and time typed into a title, like "Call Sam tomorrow at 3pm".
struct TypedDate {
    let date: Date
    /// False for a day with no time, like "on Friday".
    let hasTime: Bool
    /// The title with the date words taken out.
    let remainingTitle: String

    var label: String {
        let day: String
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            day = "Today"
        } else if calendar.isDateInTomorrow(date) {
            day = "Tomorrow"
        } else {
            day = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return hasTime ? "\(day), \(date.formatted(date: .omitted, time: .shortened))" : day
    }

    /// Words that only tie the date to the title, dropped along with the date.
    private static let joiningWords: Set<String> = ["at", "on", "by", "for", "due"]

    static func find(in title: String) -> TypedDate? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let date = match.date,
              let range = Range(match.range, in: title)
        else { return nil }

        let typed = title[range].lowercased()
        // The detector picks noon when no time is given, so look for a time in the words.
        let hasTime = typed.contains(where: \.isNumber) && (typed.contains(":") || typed.contains("am") || typed.contains("pm"))
            || typed.contains("noon") || typed.contains("midnight")

        var words = (title[..<range.lowerBound] + " " + title[range.upperBound...])
            .split(separator: " ")
            .map(String.init)
        while let last = words.last, joiningWords.contains(last.lowercased()) {
            words.removeLast()
        }
        let remaining = words.joined(separator: " ")
        return TypedDate(date: date, hasTime: hasTime, remainingTitle: remaining.isEmpty ? title : remaining)
    }
}
