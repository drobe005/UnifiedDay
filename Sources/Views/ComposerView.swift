import SwiftData
import SwiftUI

/// One composer for all types. Segmented control picks reminder, event, or note.
/// Design target: under 10 seconds from open to saved.
struct ComposerView: View {
    @Environment(EventKitService.self) private var eventKit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    enum DraftKind: Identifiable {
        case event, reminder, note
        var id: Self { self }
    }

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
    /// The new note's text and formatting. Saved only when you tap Save.
    @State private var draft = Note()
    /// A taller writing box, for longer notes.
    @State private var isExpanded = false
    /// Making an event or task from this note.
    @State private var creatingForNote: DraftKind?

    /// When set, the composer writes a note for this item and hides the type picker.
    private let attachedItem: TimelineItem?
    /// When set, the composer makes an event or task for a note and hands it back.
    private let onCreate: ((TimelineItem) -> Void)?

    init(
        initialDate: Date = .now,
        initialKind: DraftKind = .reminder,
        attachingTo item: TimelineItem? = nil,
        initialTitle: String = "",
        onCreate: ((TimelineItem) -> Void)? = nil
    ) {
        _date = State(initialValue: initialDate)
        _kind = State(initialValue: initialKind)
        _title = State(initialValue: initialTitle)
        attachedItem = item
        self.onCreate = onCreate
    }

    private var kindOptions: [(DraftKind, String)] {
        onCreate == nil
            ? [(.reminder, "Task"), (.event, "Event"), (.note, "Note")]
            : [(.reminder, "Task"), (.event, "Event")]
    }

    private var navigationTitle: String {
        switch kind {
        case .event: "New Event"
        case .reminder: "New Task"
        case .note: "New Note"
        }
    }

    private var canSave: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespaces).isEmpty
        return hasTitle || (kind == .note && !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if attachedItem == nil {
                        UDTextTabs(
                            options: kindOptions,
                            selection: $kind
                        )
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Type")
                        .listRowSeparator(.hidden)
                    }
                    TextField("Add a title", text: $title, axis: .vertical)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(UD.textPrimary)
                        .focused($titleFocused)
                        .padding(.vertical, 6)
                        .listRowSeparator(.hidden, edges: .top)
                    if kind != .note, let found = TypedDate.find(in: title) {
                        Button {
                            useTypedDate(found)
                        } label: {
                            Label("Set date: \(found.label)", systemImage: "calendar.badge.plus")
                        }
                        .udLinkRow()
                    }
                }
                .udFormRow()

                if kind == .note {
                    Section {
                        if #available(iOS 26.0, *) {
                            RichNoteEditor(note: draft, minHeight: isExpanded ? 520 : 240)
                                .listRowSeparator(.hidden)
                        } else {
                            TextField("Write something", text: Binding { draft.text } set: { draft.text = $0 }, axis: .vertical)
                                .lineLimit((isExpanded ? 20 : 8)...)
                                .padding(.vertical, 8)
                                .listRowSeparator(.hidden)
                        }
                    } header: {
                        HStack {
                            UDFormHeader(title: "Note")
                            Spacer()
                            Button {
                                withAnimation(.snappy) { isExpanded.toggle() }
                            } label: {
                                Image(systemName: isExpanded
                                    ? "arrow.down.right.and.arrow.up.left"
                                    : "arrow.up.left.and.arrow.down.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(UD.brand600)
                                    .frame(width: 44, height: 32, alignment: .trailing)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel(isExpanded ? "Smaller writing box" : "Bigger writing box")
                        }
                    } footer: {
                        UDSavedInAppNote()
                    }
                    .udFormRow()

                    Section {
                        NoteFolderPicker(selection: $folder)
                    } header: {
                        UDFormHeader(title: "Folder")
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
                        Button("New Event for This Note", systemImage: "calendar.badge.plus") {
                            creatingForNote = .event
                        }
                        .udLinkRow()
                        Button("New Task for This Note", systemImage: "checkmark.circle.badge.plus") {
                            creatingForNote = .reminder
                        }
                        .udLinkRow()
                        Button("Attach Existing Events or Tasks", systemImage: "plus") {
                            showingItemPicker = true
                        }
                        .udLinkRow()
                    } header: {
                        UDFormHeader(title: "Attached to")
                    }
                    .udFormRow()
                } else {
                    Section {
                        // Date and time are two rows over the same value, as in the design.
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                        Toggle("Include time", isOn: $includeTime)
                        if includeTime {
                            DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                        }
                        RepeatPicker(selection: $repeatOption)
                        if kind == .event {
                            Picker("Calendar", selection: $selectedCalendarID) {
                                ForEach(eventKit.writableEventCalendars(), id: \.calendarIdentifier) { calendar in
                                    Text(calendar.title).tag(Optional(calendar.calendarIdentifier))
                                }
                            }
                            .udPickerValue()
                        } else {
                            Picker("List", selection: $selectedListID) {
                                ForEach(eventKit.writableReminderLists(), id: \.calendarIdentifier) { list in
                                    Text(list.title).tag(Optional(list.calendarIdentifier))
                                }
                            }
                            .udPickerValue()
                        }
                    }
                    .udFormRow()
                    .udValuePicker()

                    Section {
                        TextField("Optional", text: $notes, axis: .vertical)
                            .lineLimit(4...)
                            .padding(.vertical, 8)
                            .listRowSeparator(.hidden)
                    } header: {
                        UDFormHeader(title: "Apple notes")
                    }
                    .udFormRow()
                }
            }
            .udFormBackground()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            // The tabs already say what is being made, so the bar shows only the buttons.
            .toolbar(removing: .title)
            .sheet(isPresented: $showingItemPicker) {
                ItemPickerView(isAttached: isAttached) { items in
                    attachments += items
                }
            }
            .sheet(item: $creatingForNote) { newKind in
                ComposerView(initialKind: newKind, initialTitle: title) { item in
                    attachments.append(item)
                }
                .environment(eventKit)
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
                    UDToolbarCancelButton { dismiss() }
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
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.body.weight(.medium))
                .foregroundStyle(UD.textPrimary)
            Text(item.scheduleLabel)
                .font(.subheadline)
                .foregroundStyle(UD.textTertiary)
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if kind == .note {
            let note = draft
            note.title = trimmed
            note.createdAt = .now
            note.updatedAt = .now
            modelContext.insert(note)
            note.folder = folder
            note.attach([attachedItem].compactMap { $0 } + attachments, in: modelContext)
            modelContext.saveNotes(reportingTo: eventKit)
        } else if kind == .event {
            let calendar = eventKit.writableEventCalendars().first { $0.calendarIdentifier == selectedCalendarID }
            let start = includeTime ? date : Calendar.current.startOfDay(for: date)
            let end = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
            let created = eventKit.createEvent(
                title: trimmed,
                start: start,
                end: end,
                isAllDay: !includeTime,
                calendar: calendar,
                notes: notes.isEmpty ? nil : notes,
                repeatOption: repeatOption
            )
            if let created { onCreate?(created) }
        } else {
            let list = eventKit.writableReminderLists().first { $0.calendarIdentifier == selectedListID }
            let created = eventKit.createReminder(
                title: trimmed,
                dueDate: date,
                includeTime: includeTime,
                list: list,
                notes: notes.isEmpty ? nil : notes,
                repeatOption: repeatOption
            )
            if let created { onCreate?(created) }
        }
        dismiss()
    }
}

/// Repeat choices for events and reminders. Shows Custom only when an item
/// already repeats in a way made in Apple's apps.
struct RepeatPicker: View {
    @Binding var selection: RepeatOption
    /// Words for a repeat made in Apple's apps, like "Every 3 days". Shown in place of "Custom".
    var customLabel: String?
    @State private var keepsCustom = false

    var body: some View {
        Picker("Repeat", selection: $selection) {
            ForEach(RepeatOption.choices) { Text($0.label).tag($0) }
            // Stays listed after picking another choice, so the original rule can be kept.
            if selection == .custom || keepsCustom {
                Text(customLabel ?? RepeatOption.custom.label).tag(RepeatOption.custom)
            }
        }
        .udPickerValue()
        .onAppear { if selection == .custom { keepsCustom = true } }
    }
}

/// The message under a delete prompt for a repeating item.
enum RepeatDeleteCopy {
    static func message(for item: TimelineItem) -> String {
        if item.isRepeatingEvent {
            return "This is a repeating event. It will also be removed from Apple Calendar."
        }
        if item.isRepeatingReminder {
            guard let next = item.nextOccurrenceDate else {
                return "It repeats \(item.repeatLabel.lowercased()). Deleting removes the whole series from Apple Reminders."
            }
            let day = next.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            return "It repeats \(item.repeatLabel.lowercased()). Deleting only this one moves it to \(day)."
        }
        return "It will also be removed from Apple \(item.kind == .reminder ? "Reminders" : "Calendar")."
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
