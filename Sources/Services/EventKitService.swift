import EventKit
import SwiftUI

/// Single gateway to Apple Calendar and Reminders. EventKit is the source of truth.
/// No local persistence in v0.1: every read and write goes through EKEventStore.
@MainActor
@Observable
final class EventKitService {
    private let store = EKEventStore()

    var accessGranted = false
    var lastError: String?
    /// Bumps whenever Calendar or Reminders data changes, inside or outside the app.
    /// Views reload when it changes so edits made in Apple's apps show up here.
    private(set) var changeCount = 0

    init() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.changeCount += 1 }
        }
    }

    // MARK: - Access

    /// Requests full access to events and reminders. Call once from onboarding.
    /// Returns true only when both are granted.
    func requestAccess() async -> Bool {
        do {
            let eventsOK = try await store.requestFullAccessToEvents()
            let remindersOK = try await store.requestFullAccessToReminders()
            let granted = eventsOK && remindersOK
            await MainActor.run { self.accessGranted = granted }
            return granted
        } catch {
            await MainActor.run { self.lastError = error.localizedDescription }
            return false
        }
    }

    func refreshAccessStatus() {
        let events = EKEventStore.authorizationStatus(for: .event)
        let reminders = EKEventStore.authorizationStatus(for: .reminder)
        accessGranted = (events == .fullAccess && reminders == .fullAccess)
    }

    // MARK: - Reads

    /// Fetches everything for one day: timed events, all-day events, reminders
    /// due that day, plus overdue reminders pinned by the sort rule.
    func fetchTimeline(for date: Date) async -> [TimelineItem] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        var items: [TimelineItem] = []
        items += fetchEvents(start: startOfDay, end: endOfDay)
        items += await fetchRemindersDue(before: endOfDay)
        return Self.sortItems(items)
    }

    private func fetchEvents(start: Date, end: Date) -> [TimelineItem] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { event in
            TimelineItem(
                id: "event-\(event.eventIdentifier ?? UUID().uuidString)",
                kind: .event,
                title: event.title ?? "(No title)",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                hasDueTime: true,
                sourceName: event.calendar.title,
                sourceColor: Color(event.calendar.cgColor),
                isCompleted: false,
                notes: event.notes,
                isReadOnly: !event.calendar.allowsContentModifications,
                occurrenceDate: event.occurrenceDate,
                storeIdentifier: event.eventIdentifier ?? ""
            )
        }
    }

    private func fetchRemindersDue(before endOfDay: Date) async -> [TimelineItem] {
        // A due-date range excludes reminders with no due date, which is what we
        // want for the Today timeline. The Reminders tab handles dateless items.
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: Date.distantPast,
            ending: endOfDay,
            calendars: nil
        )
        return await fetchReminders(matching: predicate)
    }

    /// EventKit only offers a completion-handler fetch. Rows are built inside the
    /// callback so non-Sendable EKReminder objects never cross actors.
    private func fetchReminders(matching predicate: NSPredicate) async -> [TimelineItem] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(Self.timelineItem(from:)))
            }
        }
    }

    /// Every incomplete reminder in the given lists (or all lists when nil).
    /// Used by the Reminders tab. Callers filter by date in Swift.
    func fetchAllIncompleteReminders(in lists: [EKCalendar]? = nil) async -> [TimelineItem] {
        let targets = lists ?? reminderLists()
        var items: [TimelineItem] = []
        for list in targets {
            // nil start and nil end means no date filter: all incomplete reminders.
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: [list]
            )
            items += await fetchReminders(matching: predicate)
        }
        return items
    }

    nonisolated private static func timelineItem(from reminder: EKReminder) -> TimelineItem {
        let due = reminder.dueDateComponents
        return TimelineItem(
            id: "reminder-\(reminder.calendarItemIdentifier)",
            kind: .reminder,
            title: reminder.title ?? "(No title)",
            // dueDateComponents often lack a calendar, so resolve them explicitly.
            startDate: due.flatMap { Calendar.current.date(from: $0) },
            endDate: nil,
            isAllDay: false,
            hasDueTime: due?.hour != nil,
            sourceName: reminder.calendar.title,
            sourceColor: Color(reminder.calendar.cgColor),
            isCompleted: reminder.isCompleted,
            notes: reminder.notes,
            isReadOnly: !reminder.calendar.allowsContentModifications,
            occurrenceDate: nil,
            storeIdentifier: reminder.calendarItemIdentifier
        )
    }

    /// All reminder lists, for the Reminders tab and the composer picker.
    func reminderLists() -> [EKCalendar] {
        store.calendars(for: .reminder)
    }

    /// All event calendars, for the composer picker.
    func eventCalendars() -> [EKCalendar] {
        store.calendars(for: .event)
    }

    // MARK: - Writes

    func setReminderCompleted(_ item: TimelineItem, completed: Bool) {
        guard item.kind == .reminder,
              let reminder = store.calendarItem(withIdentifier: item.storeIdentifier) as? EKReminder
        else { return }
        reminder.isCompleted = completed
        do {
            try store.save(reminder, commit: true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func createEvent(title: String, start: Date, end: Date, isAllDay: Bool, calendar: EKCalendar?, notes: String?) {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = isAllDay
        event.notes = notes
        event.calendar = calendar ?? store.defaultCalendarForNewEvents
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func createReminder(title: String, dueDate: Date?, list: EKCalendar?, notes: String?) {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: dueDate
            )
        }
        reminder.calendar = list ?? store.defaultCalendarForNewReminders()
        do {
            try store.save(reminder, commit: true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Saves edits to an event. Only this occurrence changes for repeating events.
    /// Returns false and sets `lastError` on failure.
    @discardableResult
    func updateEvent(_ item: TimelineItem, title: String, start: Date, end: Date, isAllDay: Bool, notes: String?) -> Bool {
        guard let event = event(for: item) else {
            lastError = "That event no longer exists. It may have been deleted in Calendar."
            return false
        }
        event.title = title
        event.isAllDay = isAllDay
        event.startDate = start
        event.endDate = max(end, start)
        event.notes = notes
        do {
            try store.save(event, span: .thisEvent, commit: true)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Saves edits to a reminder. A nil `dueDate` clears the due date.
    /// Returns false and sets `lastError` on failure.
    @discardableResult
    func updateReminder(_ item: TimelineItem, title: String, dueDate: Date?, includeTime: Bool, notes: String?) -> Bool {
        guard let reminder = store.calendarItem(withIdentifier: item.storeIdentifier) as? EKReminder else {
            lastError = "That reminder no longer exists. It may have been deleted in Reminders."
            return false
        }
        reminder.title = title
        reminder.notes = notes
        if let dueDate {
            let fields: Set<Calendar.Component> = includeTime
                ? [.year, .month, .day, .hour, .minute]
                : [.year, .month, .day]
            reminder.dueDateComponents = Calendar.current.dateComponents(fields, from: dueDate)
        } else {
            reminder.dueDateComponents = nil
        }
        do {
            try store.save(reminder, commit: true)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    enum RescheduleTarget {
        case today, tomorrow, nextWeek

        /// The day this target points at, counted from today (not from the old due date),
        /// so an overdue reminder moved to "Tomorrow" lands on tomorrow.
        func day(from now: Date = .now, calendar: Calendar = .current) -> Date {
            let today = calendar.startOfDay(for: now)
            switch self {
            case .today:
                return today
            case .tomorrow:
                return calendar.date(byAdding: .day, value: 1, to: today) ?? today
            case .nextWeek:
                // First day of next week in the user's locale (Sunday or Monday).
                let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: today) ?? today
                return calendar.dateInterval(of: .weekOfYear, for: nextWeek)?.start ?? nextWeek
            }
        }
    }

    /// Moves a reminder to a new day, keeping its time of day when it has one.
    /// Reminders without a due date get a date-only due date.
    @discardableResult
    func reschedule(_ item: TimelineItem, to target: RescheduleTarget) -> Bool {
        guard item.kind == .reminder else { return false }
        let calendar = Calendar.current
        var newDue = target.day(calendar: calendar)
        if item.hasDueTime, let oldDue = item.startDate {
            let time = calendar.dateComponents([.hour, .minute], from: oldDue)
            newDue = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: newDue) ?? newDue
        }
        return updateReminder(
            item,
            title: item.title,
            dueDate: newDue,
            includeTime: item.hasDueTime && item.startDate != nil,
            notes: item.notes
        )
    }

    /// event(withIdentifier:) returns the first occurrence of a repeating event,
    /// so look up the exact occurrence by its date when we have one.
    private func event(for item: TimelineItem) -> EKEvent? {
        guard item.kind == .event else { return nil }
        if let occurrence = item.occurrenceDate,
           let dayAfter = Calendar.current.date(byAdding: .day, value: 1, to: occurrence) {
            let predicate = store.predicateForEvents(
                withStart: occurrence.addingTimeInterval(-1),
                end: dayAfter,
                calendars: nil
            )
            if let match = store.events(matching: predicate).first(where: {
                $0.eventIdentifier == item.storeIdentifier && $0.occurrenceDate == occurrence
            }) {
                return match
            }
        }
        return store.event(withIdentifier: item.storeIdentifier)
    }

    func delete(_ item: TimelineItem) {
        do {
            switch item.kind {
            case .event:
                guard let event = event(for: item) else { return }
                try store.remove(event, span: .thisEvent, commit: true)
            case .reminder:
                guard let reminder = store.calendarItem(withIdentifier: item.storeIdentifier) as? EKReminder
                else { return }
                try store.remove(reminder, commit: true)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Sorting (matches spec section 9)

    private static func rank(_ item: TimelineItem) -> Int {
        if item.isOverdue { return 0 }
        if item.isTimed { return 1 }
        if item.isAllDay { return 2 }
        return 3
    }

    static func sortItems(_ items: [TimelineItem]) -> [TimelineItem] {
        items.sorted {
            let ra = rank($0), rb = rank($1)
            if ra != rb { return ra < rb }
            switch ($0.startDate, $1.startDate) {
            case let (a?, b?) where a != b: return a < b
            case (.some, nil): return true
            case (nil, .some): return false
            default: return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
    }
}
