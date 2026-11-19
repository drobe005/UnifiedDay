import AppIntents
import EventKit
import WidgetKit

/// The check circle on a widget reminder row. Marks the reminder done in Apple
/// Reminders, then WidgetKit reloads the widget so the row drops off.
struct CompleteReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let description = IntentDescription("Marks a task as done.")
    static let isDiscoverable = false

    @Parameter(title: "Reminder ID")
    var reminderID: String

    init() {}

    init(reminderID: String) {
        self.reminderID = reminderID
    }

    func perform() async throws -> some IntentResult {
        guard DayLoader.hasAccess else { return .result() }
        let store = EKEventStore()
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            return .result()
        }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
        return .result()
    }
}
