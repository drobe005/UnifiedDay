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
    static let alertsEnabledKey = "alertsEnabled"
    static let alertLeadMinutesKey = "alertLeadMinutes"
    static let defaultAlertLeadMinutes = 10

    /// iOS keeps at most 64 pending alerts per app, so schedule only the soonest.
    private static let maxPendingAlerts = 60
    private static let alertWindowDays = 14
    /// When reminders with a date but no time alert, as an hour of the day.
    private static let dateOnlyAlertHour = 9
    /// The notification center holds its delegate weakly, so keep it here.
    private static let alertPresenter = AlertPresenter()

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
        UNUserNotificationCenter.current().delegate = Self.alertPresenter
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

    /// Fetches everything for one day: timed events, all-day events, and reminders
    /// due that day. Today also includes overdue reminders, pinned by the sort rule.
    func fetchTimeline(for date: Date) async -> [TimelineItem] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        var items: [TimelineItem] = []
        items += fetchEvents(start: startOfDay, end: endOfDay)
        let reminders = await fetchRemindersDue(before: endOfDay)
        items += calendar.isDateInToday(date)
            ? reminders
            : reminders.filter { ($0.startDate ?? .distantPast) >= startOfDay }
        return Self.sortItems(items)
    }

    /// The start of every day in the range that has an event or an open reminder.
    /// Multi-day events mark each day they touch. Used for the calendar dots.
    func daysWithItems(from start: Date, to end: Date) async -> Set<Date> {
        let calendar = Calendar.current
        var days = Set<Date>()
        for event in fetchEvents(start: start, end: end) {
            guard let eventStart = event.startDate else { continue }
            // An event ending exactly at midnight does not touch the next day.
            let last = max(eventStart, (event.endDate ?? eventStart).addingTimeInterval(-1))
            var day = calendar.startOfDay(for: max(eventStart, start))
            while day <= last, day < end {
                days.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        for reminder in await fetchRemindersDue(before: end) {
            if let due = reminder.startDate, due >= start, due < end {
                days.insert(calendar.startOfDay(for: due))
            }
        }
        return days
    }

    private func fetchEvents(start: Date, end: Date) -> [TimelineItem] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map(timelineItem(from:))
    }

    private func timelineItem(from event: EKEvent) -> TimelineItem {
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
            storeIdentifier: event.eventIdentifier ?? "",
            externalIdentifier: event.calendarItemExternalIdentifier ?? "",
            repeatOption: Self.repeatOption(for: event)
        )
    }

    // MARK: - Repeats

    nonisolated private static let weekdays: Set<EKWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    /// Maps Apple's recurrence rule to one of the app's choices, or `custom`.
    nonisolated private static func repeatOption(for item: EKCalendarItem) -> RepeatOption {
        guard let rules = item.recurrenceRules, !rules.isEmpty else { return .never }
        guard rules.count == 1, let rule = rules.first,
              rule.daysOfTheMonth == nil, rule.monthsOfTheYear == nil,
              rule.weeksOfTheYear == nil, rule.daysOfTheYear == nil, rule.setPositions == nil
        else { return .custom }
        let days = Set((rule.daysOfTheWeek ?? []).map(\.dayOfTheWeek))
        switch (rule.frequency, rule.interval) {
        case (.daily, 1) where days.isEmpty: return .daily
        case (.weekly, 1) where days == weekdays: return .weekdays
        case (.weekly, 1) where days.count <= 1: return .weekly
        case (.weekly, 2) where days.count <= 1: return .biweekly
        case (.monthly, 1) where days.isEmpty: return .monthly
        case (.yearly, 1) where days.isEmpty: return .yearly
        default: return .custom
        }
    }

    /// The rule for a choice. Nil for never; `custom` is never written.
    private static func recurrenceRule(for option: RepeatOption) -> EKRecurrenceRule? {
        switch option {
        case .never, .custom:
            return nil
        case .daily:
            return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekdays:
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                daysOfTheWeek: weekdays.map { EKRecurrenceDayOfWeek($0) },
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: nil
            )
        case .weekly:
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .biweekly:
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: nil)
        case .monthly:
            return EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        case .yearly:
            return EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        }
    }

    private static func applyRepeat(_ option: RepeatOption, to item: EKCalendarItem) {
        guard option != .custom else { return }
        item.recurrenceRules = recurrenceRule(for: option).map { [$0] }
    }

    /// Finds the event or reminder a note is attached to. Tries the identifier shared
    /// across devices first, then the local one. Repeating events open on their next
    /// occurrence, so edits don't land on one in the past.
    func item(kind: TimelineItemKind, externalID: String, localID: String) -> TimelineItem? {
        let matches = externalID.isEmpty ? [] : store.calendarItems(withExternalIdentifier: externalID)
        switch kind {
        case .reminder:
            let reminder = matches.compactMap { $0 as? EKReminder }.first
                ?? store.calendarItem(withIdentifier: localID) as? EKReminder
            return reminder.map(Self.timelineItem(from:))
        case .event:
            guard let event = matches.compactMap({ $0 as? EKEvent }).first ?? store.event(withIdentifier: localID) else {
                return nil
            }
            return timelineItem(from: nextOccurrence(of: event))
        }
    }

    private func nextOccurrence(of event: EKEvent) -> EKEvent {
        guard event.hasRecurrenceRules,
              let end = Calendar.current.date(byAdding: .year, value: 1, to: .now) else { return event }
        let predicate = store.predicateForEvents(withStart: .now, end: end, calendars: [event.calendar])
        return store.events(matching: predicate)
            .filter { $0.eventIdentifier == event.eventIdentifier }
            .min { $0.startDate < $1.startDate } ?? event
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
            storeIdentifier: reminder.calendarItemIdentifier,
            externalIdentifier: reminder.calendarItemExternalIdentifier ?? "",
            repeatOption: repeatOption(for: reminder)
        )
    }

    /// Searches titles and notes across events in the next `days` days and reminders
    /// that are overdue, dateless, or due in that window. Chronological, dateless last.
    func search(_ query: String, days: Int = 30) async -> [TimelineItem] {
        await upcomingItems(days: days).filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.notes?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    /// Events in the next `days` days plus reminders that are overdue, dateless, or
    /// due in that window. Chronological, dateless last.
    func upcomingItems(days: Int = 30) async -> [TimelineItem] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else { return [] }

        let reminders = await fetchAllIncompleteReminders().filter { item in
            guard let due = item.startDate else { return true }
            return due < end
        }
        return (fetchEvents(start: start, end: end) + reminders)
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

    /// Makes a new Apple Reminders list in the same account as the default list,
    /// usually iCloud. Returns false and sets `lastError` on failure.
    @discardableResult
    func createReminderList(named title: String) -> Bool {
        guard let source = store.defaultCalendarForNewReminders()?.source else {
            lastError = "Couldn't find a Reminders account to add the list to."
            return false
        }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = title
        list.source = source
        do {
            try store.saveCalendar(list, commit: true)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Events and open reminders between two days, for the Calendar tab's week,
    /// month, and custom views. Overdue reminders only show on their own day.
    func fetchRange(from start: Date, to end: Date) async -> [TimelineItem] {
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: start,
            ending: end,
            calendars: nil
        )
        let reminders = await fetchReminders(matching: predicate)
        return Self.sortItems(fetchEvents(start: start, end: end) + reminders)
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

    // MARK: - Needs attention and badge

    /// Incomplete reminders that are overdue or due today, in timeline order.
    /// This is the list behind the bell and the app icon badge.
    func fetchNeedsAttention() async -> [TimelineItem] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: .now)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }
        return Self.sortItems(await fetchRemindersDue(before: endOfDay))
    }

    /// Asks iOS for badge permission. Returns false and sets `lastError` if refused.
    /// Includes alerts and sound because iOS only asks once: a badge-only first
    /// request left the Banners option out of iOS Settings.
    func enableBadge() async -> Bool {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
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
            count = await fetchNeedsAttention().count
        }
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(count)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Alerts

    /// Asks iOS for banners and sound. Checks the result directly, because iOS does
    /// not ask again when badge permission was already answered.
    /// Returns false and sets `lastError` if banners are off.
    func enableAlerts() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            lastError = error.localizedDescription
            return false
        }
        guard await center.notificationSettings().alertSetting == .enabled else {
            lastError = "Allow alerts for UnifiedDay in iOS Settings, under Notifications."
            return false
        }
        return true
    }

    /// Whether iOS shows banners for this app. Only iOS Settings can change this.
    func bannersAllowed() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().alertStyle != .none
    }

    /// Replaces all scheduled alerts with the soonest upcoming events and reminders.
    /// iOS only lets this run while the app is open, so later changes wait for the next open.
    func refreshAlerts() async {
        let center = UNUserNotificationCenter.current()
        guard accessGranted, UserDefaults.standard.bool(forKey: Self.alertsEnabledKey),
              let end = Calendar.current.date(byAdding: .day, value: Self.alertWindowDays, to: .now)
        else {
            center.removeAllPendingNotificationRequests()
            return
        }

        let now = Date.now
        let items = await fetchRemindersDue(before: end) + fetchEvents(start: now, end: end)
        guard !Task.isCancelled else { return }

        let upcoming = items
            .compactMap { item in alertDate(for: item).map { (item: item, date: $0) } }
            .filter { $0.date > now }
            .sorted { $0.date < $1.date }
            .prefix(Self.maxPendingAlerts)

        center.removeAllPendingNotificationRequests()
        do {
            for alert in upcoming {
                try await center.add(alertRequest(for: alert.item, at: alert.date))
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Timed events alert ahead of their start, by the lead time in Settings.
    /// Reminders alert when due, or in the morning without a time. All-day events do not alert.
    private func alertDate(for item: TimelineItem) -> Date? {
        guard let start = item.startDate, !item.isAllDay else { return nil }
        switch item.kind {
        case .event:
            let saved = UserDefaults.standard.object(forKey: Self.alertLeadMinutesKey) as? Int
            let minutes = saved ?? Self.defaultAlertLeadMinutes
            return start.addingTimeInterval(TimeInterval(-minutes * 60))
        case .reminder:
            guard !item.hasDueTime else { return start }
            return Calendar.current.date(bySettingHour: Self.dateOnlyAlertHour, minute: 0, second: 0, of: start)
        }
    }

    private func alertRequest(for item: TimelineItem, at date: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.sound = .default
        if let time = item.timeLabel {
            content.body = item.kind == .event ? "Starts at \(time)" : "Due at \(time)"
        } else {
            content.body = "Due today"
        }
        let fields = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: fields, repeats: false)
        return UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
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

    func createEvent(
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        calendar: EKCalendar?,
        notes: String?,
        repeatOption: RepeatOption = .never
    ) {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = isAllDay
        event.notes = notes
        event.calendar = calendar ?? preferredEventCalendar()
        Self.applyRepeat(repeatOption, to: event)
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Repeats need a due date, so `repeatOption` is ignored without one.
    func createReminder(
        title: String,
        dueDate: Date?,
        includeTime: Bool,
        list: EKCalendar?,
        notes: String?,
        repeatOption: RepeatOption = .never
    ) {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        if let dueDate {
            reminder.dueDateComponents = dueComponents(for: dueDate, includeTime: includeTime)
            Self.applyRepeat(repeatOption, to: reminder)
        }
        reminder.calendar = list ?? preferredReminderList()
        do {
            try store.save(reminder, commit: true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Saves edits to an event. Only this occurrence changes for repeating events,
    /// unless the repeat changes: then this and every later occurrence change.
    /// Returns false and sets `lastError` on failure.
    @discardableResult
    func updateEvent(
        _ item: TimelineItem,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        calendarID: String? = nil,
        notes: String?,
        repeatOption: RepeatOption? = nil
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
        var span = EKSpan.thisEvent
        if let repeatOption, repeatOption != item.repeatOption {
            Self.applyRepeat(repeatOption, to: event)
            span = .futureEvents
        }
        do {
            try store.save(event, span: span, commit: true)
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
        notes: String?,
        repeatOption: RepeatOption? = nil
    ) -> Bool {
        guard let reminder = store.calendarItem(withIdentifier: item.storeIdentifier) as? EKReminder else {
            lastError = "That reminder no longer exists. It may have been deleted in Reminders."
            return false
        }
        reminder.title = title
        reminder.notes = notes
        reminder.dueDateComponents = dueDate.map { dueComponents(for: $0, includeTime: includeTime) }
        if dueDate == nil {
            // Apple's Reminders can't repeat a reminder without a due date.
            reminder.recurrenceRules = nil
        } else if let repeatOption, repeatOption != item.repeatOption {
            Self.applyRepeat(repeatOption, to: reminder)
        }
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

    enum RescheduleTarget: Equatable {
        case today, tomorrow, nextWeek
        /// A day picked by the person. Any time on it is ignored.
        case day(Date)

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
            case .day(let date):
                return calendar.startOfDay(for: date)
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

/// Shows alerts as banners while the app is open. iOS hides them otherwise.
final class AlertPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
