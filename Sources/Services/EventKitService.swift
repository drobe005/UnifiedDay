import EventKit
import SwiftUI
import UserNotifications

/// Single gateway to Apple Calendar and Reminders. EventKit is the source of truth.
/// No local persistence in v0.1: every read and write goes through EKEventStore.
@MainActor
@Observable
final class EventKitService {
    /// UserDefaults keys for Settings. Views bind to these with @AppStorage.
    static let badgeEnabledKey = "badgeEnabled"
    static let defaultCalendarKey = "defaultCalendarID"
    static let defaultListKey = "defaultReminderListID"

    private let store = EKEventStore()

    var accessGranted = false
    /// True when access was refused or limited, so only iOS Settings can fix it.
    var accessNeedsSettings = false
    var lastError: String?
    /// Bumps whenever Calendar or Reminders data changes, inside or outside the app.
    /// Views reload when it changes so edits made in Apple's apps show up here.
    private(set) var changeCount = 0

    init() {
        refreshAccessStatus()
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
            refreshAccessStatus()
            return eventsOK && remindersOK
        } catch {
            refreshAccessStatus()
            lastError = error.localizedDescription
            return false
        }
    }

    func refreshAccessStatus() {
        let events = EKEventStore.authorizationStatus(for: .event)
        let reminders = EKEventStore.authorizationStatus(for: .reminder)
        accessGranted = (events == .fullAccess && reminders == .fullAccess)
        accessNeedsSettings = !accessGranted && events != .notDetermined && reminders != .notDetermined
    }

    /// Re-checks access and asks views to reload. Call when the app returns to the foreground.
    func refreshOnForeground() {
        refreshAccessStatus()
        changeCount += 1
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
                // Occurrences of a repeating event share an identifier, so add the date.
                id: "event-\(event.eventIdentifier ?? UUID().uuidString)-\(event.occurrenceDate.timeIntervalSince1970)",
                kind: .event,
                title: event.title ?? "(No title)",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                hasDueTime: true,
                sourceID: event.calendar.calendarIdentifier,
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
            sourceID: reminder.calendar.calendarIdentifier,
            sourceName: reminder.calendar.title,
            sourceColor: Color(reminder.calendar.cgColor),
            isCompleted: reminder.isCompleted,
            notes: reminder.notes,
            isReadOnly: !reminder.calendar.allowsContentModifications,
            occurrenceDate: nil,
            storeIdentifier: reminder.calendarItemIdentifier
        )
    }

    /// Searches titles and notes across events in the next `days` days and reminders
    /// that are overdue, dateless, or due in that window. Chronological, dateless last.
    func search(_ query: String, days: Int = 30) async -> [TimelineItem] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else { return [] }

        let reminders = await fetchAllIncompleteReminders().filter { item in
            guard let due = item.startDate else { return true }
            return due < end
        }
        return (fetchEvents(start: start, end: end) + reminders)
            .filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || ($0.notes?.localizedCaseInsensitiveContains(query) ?? false)
            }
            .sorted {
                switch ($0.startDate, $1.startDate) {
                case let (a?, b?) where a != b: return a < b
                case (.some, nil): return true
                case (nil, .some): return false
                default: return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
            }
    }

    /// All reminder lists, for the Reminders tab.
    func reminderLists() -> [EKCalendar] {
        store.calendars(for: .reminder)
    }

    /// Reminder lists that accept changes, for pickers.
    func writableReminderLists() -> [EKCalendar] {
        reminderLists().filter(\.allowsContentModifications)
    }

    /// Event calendars that accept changes, for pickers.
    func writableEventCalendars() -> [EKCalendar] {
        store.calendars(for: .event).filter(\.allowsContentModifications)
    }

    /// The default chosen in Settings, or Apple's default when none is set or it is gone.
    func preferredEventCalendar() -> EKCalendar? {
        let saved = UserDefaults.standard.string(forKey: Self.defaultCalendarKey)
        return writableEventCalendars().first { $0.calendarIdentifier == saved }
            ?? store.defaultCalendarForNewEvents
    }

    /// The default chosen in Settings, or Apple's default when none is set or it is gone.
    func preferredReminderList() -> EKCalendar? {
        let saved = UserDefaults.standard.string(forKey: Self.defaultListKey)
        return writableReminderLists().first { $0.calendarIdentifier == saved }
            ?? store.defaultCalendarForNewReminders()
    }

    // MARK: - Badge

    /// Asks iOS for badge permission. Returns false and sets `lastError` if refused.
    func enableBadge() async -> Bool {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.badge])
            if !allowed {
                lastError = "Allow badges for UnifiedDay in iOS Settings, under Notifications."
            }
            return allowed
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Sets the app icon badge to incomplete reminders due today plus overdue.
    /// iOS only updates it while the app runs, so it can lag until the next open.
    func refreshBadge() async {
        var count = 0
        if accessGranted, UserDefaults.standard.bool(forKey: Self.badgeEnabledKey) {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: .now)
            if let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) {
                count = await fetchRemindersDue(before: endOfDay).count
            }
        }
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(count)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Writes

    func setReminderCompleted(_ item: TimelineItem, completed: Bool) {
        guard item.kind == .reminder,
              let reminder = store.calendarItem(withIdentifier: item.storeIdentifier) as? EKReminder
        else {
            lastError = "That reminder no longer exists. It may have been deleted in Reminders."
            return
        }
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
        event.calendar = calendar ?? preferredEventCalendar()
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func createReminder(title: String, dueDate: Date?, includeTime: Bool, list: EKCalendar?, notes: String?) {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        if let dueDate {
            reminder.dueDateComponents = dueComponents(for: dueDate, includeTime: includeTime)
        }
        reminder.calendar = list ?? preferredReminderList()
        do {
            try store.save(reminder, commit: true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Saves edits to an event. Only this occurrence changes for repeating events.
    /// Returns false and sets `lastError` on failure.
    @discardableResult
    func updateEvent(
        _ item: TimelineItem,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        calendarID: String? = nil,
        notes: String?
    ) -> Bool {
        guard let event = event(for: item) else {
            lastError = "That event no longer exists. It may have been deleted in Calendar."
            return false
        }
        event.title = title
        event.isAllDay = isAllDay
        event.startDate = start
        event.endDate = max(end, start)
        event.notes = notes
        if let calendarID, calendarID != item.sourceID, let calendar = store.calendar(withIdentifier: calendarID) {
            event.calendar = calendar
        }
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
    func updateReminder(
        _ item: TimelineItem,
        title: String,
        dueDate: Date?,
        includeTime: Bool,
        listID: String? = nil,
        notes: String?
    ) -> Bool {
        guard let reminder = store.calendarItem(withIdentifier: item.storeIdentifier) as? EKReminder else {
            lastError = "That reminder no longer exists. It may have been deleted in Reminders."
            return false
        }
        reminder.title = title
        reminder.notes = notes
        reminder.dueDateComponents = dueDate.map { dueComponents(for: $0, includeTime: includeTime) }
        if let listID, listID != item.sourceID, let list = store.calendar(withIdentifier: listID) {
            reminder.calendar = list
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

    private func dueComponents(for date: Date, includeTime: Bool) -> DateComponents {
        let fields: Set<Calendar.Component> = includeTime
            ? [.year, .month, .day, .hour, .minute]
            : [.year, .month, .day]
        return Calendar.current.dateComponents(fields, from: date)
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
                guard let event = event(for: item) else {
                    lastError = "That event no longer exists. It may have been deleted in Calendar."
                    return
                }
                try store.remove(event, span: .thisEvent, commit: true)
            case .reminder:
                guard let reminder = store.calendarItem(withIdentifier: item.storeIdentifier) as? EKReminder else {
                    lastError = "That reminder no longer exists. It may have been deleted in Reminders."
                    return
                }
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
