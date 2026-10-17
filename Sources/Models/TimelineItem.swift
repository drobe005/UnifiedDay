import Foundation
import SwiftUI

/// One row in the unified timeline. Backed by EventKit, never by a local database.
enum TimelineItemKind: String {
    case event
    case reminder
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
}
