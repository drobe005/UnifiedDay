import EventKit
import SwiftUI
import WidgetKit

/// One event or reminder as the widgets show it. A trimmed copy of the app's
/// TimelineItem, since the widget runs as its own small program.
struct WidgetItem: Hashable, Identifiable, Sendable {
    enum Kind: String, Sendable { case event, reminder }

    let id: String
    let kind: Kind
    let title: String
    /// Event start or reminder due date.
    let start: Date?
    let end: Date?
    let isAllDay: Bool
    /// False for reminders due on a day with no time.
    let hasTime: Bool
    let sourceName: String
    let color: Color
    /// EKEvent.eventIdentifier or EKReminder.calendarItemIdentifier.
    let storeID: String
    let occurrence: Date?
    let isOverdue: Bool

    var isTimed: Bool { start != nil && !isAllDay && hasTime }

    var timeLabel: String? {
        guard isTimed, let start else { return nil }
        return start.formatted(date: .omitted, time: .shortened)
    }

    /// Opens this item's details in the app.
    var url: URL {
        var parts = URLComponents()
        parts.scheme = "unifiedday"
        parts.host = "item"
        parts.queryItems = [
            URLQueryItem(name: "kind", value: kind.rawValue),
            URLQueryItem(name: "id", value: storeID),
        ] + (occurrence.map { [URLQueryItem(name: "occ", value: String($0.timeIntervalSince1970))] } ?? [])
        return parts.url ?? DeepLink.today
    }
}

/// Links into the app. The app reads these in RootView.
enum DeepLink {
    static let today = URL(string: "unifiedday://today")!
    static let attention = URL(string: "unifiedday://attention")!
    static let new = URL(string: "unifiedday://new")!

    static func calendar(_ day: Date) -> URL {
        URL(string: "unifiedday://calendar?day=\(Int(day.timeIntervalSince1970))")!
    }
}

/// Everything the widgets need for today, read once per refresh.
struct DayData: Sendable {
    var accessGranted = true
    /// Today's events and open reminders (including overdue ones), in Today order.
    var items: [WidgetItem] = []
    /// Day numbers in this month that have an event or an open reminder.
    var markedDays: Set<Int> = []

    var reminders: [WidgetItem] { items.filter { $0.kind == .reminder } }
    var events: [WidgetItem] { items.filter { $0.kind == .event } }
    var overdue: [WidgetItem] { reminders.filter(\.isOverdue) }
    var dueToday: [WidgetItem] { reminders.filter { !$0.isOverdue } }

    /// The current or next timed event. Falls back to the next timed reminder.
    func upNext(at date: Date) -> WidgetItem? {
        let timed = items.filter { $0.isTimed && !$0.isOverdue }
        let events = timed.filter { $0.kind == .event && ($0.end ?? $0.start ?? date) > date }
        if let event = events.min(by: { ($0.start ?? date) < ($1.start ?? date) }) { return event }
        return timed.filter { $0.kind == .reminder && ($0.start ?? date) >= date }
            .min { ($0.start ?? date) < ($1.start ?? date) }
    }

    /// What's left today besides `upNext`, in Today order. Finished events drop off.
    func remaining(at date: Date, excluding next: WidgetItem?) -> [WidgetItem] {
        items.filter { item in
            guard item.id != next?.id else { return false }
            if item.kind == .event, item.isTimed, let end = item.end { return end > date }
            return true
        }
    }

    static let preview: DayData = {
        let calendar = Calendar.current
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        }
        let blue = Color(red: 0.16, green: 0.34, blue: 0.9)
        let green = Color(red: 0.2, green: 0.7, blue: 0.4)
        let orange = Color(red: 1, green: 0.62, blue: 0.04)
        func item(_ title: String, _ kind: WidgetItem.Kind, _ start: Date?, _ end: Date? = nil,
                  source: String, color: Color, overdue: Bool = false) -> WidgetItem {
            WidgetItem(id: title, kind: kind, title: title, start: start, end: end, isAllDay: false,
                       hasTime: start != nil, sourceName: source, color: color, storeID: "",
                       occurrence: nil, isOverdue: overdue)
        }
        let now = Date.now
        return DayData(items: [
            item("Send invoice", .reminder, calendar.date(byAdding: .day, value: -1, to: at(17)),
                 source: "Work", color: orange, overdue: true),
            item("Sprint planning", .event, now.addingTimeInterval(19 * 60), now.addingTimeInterval(79 * 60),
                 source: "Work", color: blue),
            item("Lunch with Sam", .event, now.addingTimeInterval(3 * 3600), now.addingTimeInterval(4 * 3600),
                 source: "Personal", color: green),
            item("Pick up dry cleaning", .reminder, now.addingTimeInterval(5 * 3600),
                 source: "Errands", color: orange),
            item("Gym", .event, now.addingTimeInterval(7 * 3600), now.addingTimeInterval(8 * 3600),
                 source: "Personal", color: green),
        ], markedDays: [2, 4, 9, 10, 12, 16, 18, 23, 25])
    }()
}

/// Reads today's data straight from EventKit. This is the one place outside the
/// app's EventKitService that talks to the event store, because widgets run in
/// their own process and can't reach the app.
enum DayLoader {
    static var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
            && EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    static func load(now: Date = .now) async -> DayData {
        guard hasAccess else { return DayData(accessGranted: false) }
        let store = EKEventStore()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay),
              let month = calendar.dateInterval(of: .month, for: now) else { return DayData() }

        let events = store.events(matching: store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil))
            .map { event(from: $0) }

        let reminders = await fetchReminders(store: store, start: .distantPast, end: endOfDay, startOfDay: startOfDay)
            .filter { ($0.start ?? .distantFuture) < endOfDay }

        // Days this month with something on them, for the month grid dots.
        var marked = Set<Int>()
        for event in store.events(matching: store.predicateForEvents(withStart: month.start, end: month.end, calendars: nil)) {
            guard let eventStart = event.startDate else { continue }
            let last = max(eventStart, (event.endDate ?? eventStart).addingTimeInterval(-1))
            var day = calendar.startOfDay(for: max(eventStart, month.start))
            while day <= last, day < month.end {
                marked.insert(calendar.component(.day, from: day))
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        let monthReminders = await fetchReminders(store: store, start: month.start, end: month.end, startOfDay: startOfDay)
        for reminder in monthReminders {
            if let due = reminder.start, due >= month.start, due < month.end {
                marked.insert(calendar.component(.day, from: due))
            }
        }

        return DayData(items: sort(events + reminders), markedDays: marked)
    }

    private static func fetchReminders(store: EKEventStore, start: Date, end: Date, startOfDay: Date) async -> [WidgetItem] {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: start, ending: end, calendars: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map { reminder(from: $0, startOfDay: startOfDay) })
            }
        }
    }

    private static func event(from event: EKEvent) -> WidgetItem {
        WidgetItem(
            id: "event-\(event.eventIdentifier ?? UUID().uuidString)-\(event.occurrenceDate.timeIntervalSince1970)",
            kind: .event,
            title: event.title ?? "(No title)",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            hasTime: true,
            sourceName: event.calendar.title,
            color: Color(cgColor: event.calendar.cgColor),
            storeID: event.eventIdentifier ?? "",
            occurrence: event.occurrenceDate,
            isOverdue: false
        )
    }

    private static func reminder(from reminder: EKReminder, startOfDay: Date) -> WidgetItem {
        let due = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        return WidgetItem(
            id: "reminder-\(reminder.calendarItemIdentifier)",
            kind: .reminder,
            title: reminder.title ?? "(No title)",
            start: due,
            end: nil,
            isAllDay: false,
            hasTime: reminder.dueDateComponents?.hour != nil,
            sourceName: reminder.calendar.title,
            color: Color(cgColor: reminder.calendar.cgColor),
            storeID: reminder.calendarItemIdentifier,
            occurrence: nil,
            isOverdue: (due ?? .distantFuture) < startOfDay
        )
    }

    /// Same order as the app's Today list: overdue, timed, all-day, due today without a time.
    private static func sort(_ items: [WidgetItem]) -> [WidgetItem] {
        func rank(_ item: WidgetItem) -> Int {
            if item.isOverdue { return 0 }
            if item.isTimed { return 1 }
            if item.isAllDay { return 2 }
            return 3
        }
        return items.sorted {
            let ra = rank($0), rb = rank($1)
            if ra != rb { return ra < rb }
            switch ($0.start, $1.start) {
            case let (a?, b?) where a != b: return a < b
            case (.some, nil): return true
            case (nil, .some): return false
            default: return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
    }
}

struct DayEntry: TimelineEntry {
    let date: Date
    let data: DayData
}

struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        DayEntry(date: .now, data: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (DayEntry) -> Void) {
        if context.isPreview {
            completion(DayEntry(date: .now, data: .preview))
            return
        }
        Task {
            completion(DayEntry(date: .now, data: await DayLoader.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<DayEntry>) -> Void) {
        Task {
            let now = Date.now
            let data = await DayLoader.load(now: now)
            // One entry every 5 minutes for the next hour keeps "in 19m" current.
            // The app also asks for a reload whenever calendar data changes.
            let calendar = Calendar.current
            let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            var entries = (0..<12).map { step in
                DayEntry(date: now.addingTimeInterval(Double(step) * 300), data: data)
            }.filter { $0.date < midnight }
            if entries.isEmpty { entries = [DayEntry(date: now, data: data)] }
            let reload = min(now.addingTimeInterval(3600), midnight)
            completion(Timeline(entries: entries, policy: .after(reload)))
        }
    }
}
