import Foundation
import SwiftUI

/// One row in the unified timeline. Backed by EventKit, never by a local database.
enum TimelineItemKind: String {
    case event
    case reminder
}

/// How often an event or reminder repeats. `custom` covers rules made in Apple's
/// apps that these choices can't describe; the app leaves those as they are.
enum RepeatOption: String, CaseIterable, Identifiable {
    case never, daily, weekdays, weekly, biweekly, monthly, yearly, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never: "Never"
        case .daily: "Every day"
        case .weekdays: "Every weekday"
        case .weekly: "Every week"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Every month"
        case .yearly: "Every year"
        case .custom: "Custom"
        }
    }

    /// Choices offered in pickers. Custom only shows for items that already have it.
    static let choices: [RepeatOption] = [.never, .daily, .weekdays, .weekly, .biweekly, .monthly, .yearly]
}

struct TimelineItem: Identifiable, Hashable {
    let id: String
    let kind: TimelineItemKind
    let title: String
    /// Event start (including all-day events) or reminder due date.
    let startDate: Date?
    /// Event end. Nil for reminders.
    let endDate: Date?
    let isAllDay: Bool
    /// False for reminders whose due date has no time of day. Always true for events.
    let hasDueTime: Bool
    /// EKCalendar.calendarIdentifier of the calendar or list this item lives in.
    let sourceID: String
    let sourceName: String
    let sourceColor: Color
    let isCompleted: Bool
    let notes: String?
    /// True when the calendar or list does not allow changes (shared, subscribed, birthdays).
    let isReadOnly: Bool
    /// EKEvent.occurrenceDate. Needed to find the right occurrence of a repeating event.
    let occurrenceDate: Date?
    /// EKEvent.eventIdentifier or EKReminder.calendarItemIdentifier. Used for edits.
    let storeIdentifier: String
    /// calendarItemExternalIdentifier. Stays the same across devices, so notes link by it.
    let externalIdentifier: String
    var repeatOption = RepeatOption.never

    var isOverdue: Bool {
        guard kind == .reminder, let due = startDate, !isCompleted else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }

    /// Has a specific time of day: timed events and reminders due at a time.
    var isTimed: Bool {
        startDate != nil && !isAllDay && hasDueTime
    }

    var timeLabel: String? {
        guard isTimed, let startDate else { return nil }
        return startDate.formatted(date: .omitted, time: .shortened)
    }

    /// One value per event or reminder, so all occurrences of a repeating event match.
    var linkKey: String {
        externalIdentifier.isEmpty ? id : externalIdentifier
    }

    /// The day and any time, such as "Today, 9:00 AM".
    var scheduleLabel: String {
        [dayLabel ?? "No date", timeLabel].compactMap { $0 }.joined(separator: ", ")
    }

    /// "Today", "Tomorrow", "Yesterday", or a short date. Nil without a date.
    var dayLabel: String? {
        guard let startDate else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(startDate) { return "Today" }
        if calendar.isDateInTomorrow(startDate) { return "Tomorrow" }
        if calendar.isDateInYesterday(startDate) { return "Yesterday" }
        return startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}
