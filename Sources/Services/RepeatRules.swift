import EventKit
import Foundation

/// Reads Apple repeat rules: a plain-language description, and the next date a
/// repeating reminder is due, so one occurrence can be skipped instead of deleting all.
enum RepeatRules {
    /// Words for any rule, like "Every 2 weeks on Mon and Wed" or "Every month on the last Friday".
    static func describe(_ rule: EKRecurrenceRule, calendar: Calendar = .current) -> String {
        let interval = max(rule.interval, 1)
        let unit: String = switch rule.frequency {
        case .daily: "day"
        case .weekly: "week"
        case .monthly: "month"
        case .yearly: "year"
        @unknown default: "time"
        }
        var text = interval == 1 ? "Every \(unit)" : "Every \(interval) \(unit)s"

        let weekdays = rule.daysOfTheWeek ?? []
        let positions = (rule.setPositions ?? []).map(\.intValue)
        if !weekdays.isEmpty {
            let names = sortedWeekdays(weekdays, calendar: calendar).map { day -> String in
                let name = calendar.weekdaySymbols[day.dayOfTheWeek.rawValue - 1]
                let short = calendar.shortWeekdaySymbols[day.dayOfTheWeek.rawValue - 1]
                if day.weekNumber != 0 { return "the \(ordinalWord(day.weekNumber)) \(name)" }
                if let position = positions.first, positions.count == 1 { return "the \(ordinalWord(position)) \(name)" }
                return short
            }
            text += " on " + list(names)
        }
        if let days = rule.daysOfTheMonth, !days.isEmpty {
            text += " on the " + list(days.map { $0.intValue == -1 ? "last day" : ordinalNumber($0.intValue) })
        }
        if let months = rule.monthsOfTheYear, !months.isEmpty {
            text += " in " + list(months.map { calendar.shortMonthSymbols[$0.intValue - 1] })
        }
        if let end = rule.recurrenceEnd {
            if let date = end.endDate {
                text += ", until \(date.formatted(.dateTime.month(.abbreviated).day().year()))"
            } else if end.occurrenceCount > 0 {
                text += ", \(end.occurrenceCount) times"
            }
        }
        return text
    }

    /// The next due date after `due`, keeping the time of day. Nil when the series has
    /// ended or uses a pattern this can't follow, like "the second Tuesday".
    static func nextDate(after due: Date, rule: EKRecurrenceRule, calendar: Calendar = .current) -> Date? {
        guard rule.setPositions == nil, rule.weeksOfTheYear == nil, rule.daysOfTheYear == nil,
              (rule.daysOfTheWeek ?? []).allSatisfy({ $0.weekNumber == 0 }),
              (rule.daysOfTheMonth ?? []).allSatisfy({ $0.intValue > 0 })
        else { return nil }
        let interval = max(rule.interval, 1)
        let weekdays = Set((rule.daysOfTheWeek ?? []).map(\.dayOfTheWeek.rawValue))
        let monthDays = Set((rule.daysOfTheMonth ?? []).map(\.intValue))
        let months = Set((rule.monthsOfTheYear ?? []).map(\.intValue))
        let start = calendar.startOfDay(for: due)
        let dueParts = calendar.dateComponents([.weekday, .day, .month], from: start)

        func distance(_ unit: Calendar.Component, to day: Date) -> Int {
            guard let a = calendar.dateInterval(of: unit, for: start)?.start,
                  let b = calendar.dateInterval(of: unit, for: day)?.start
            else { return 0 }
            return calendar.dateComponents([unit], from: a, to: b).value(for: unit) ?? 0
        }

        // Five years covers every rule this accepts, even yearly ones on Feb 29.
        for offset in 1...(366 * 5) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let parts = calendar.dateComponents([.weekday, .day, .month], from: day)
            let matches: Bool = switch rule.frequency {
            case .daily:
                offset % interval == 0 && (weekdays.isEmpty || weekdays.contains(parts.weekday ?? 0))
            case .weekly:
                distance(.weekOfYear, to: day) % interval == 0
                    && (weekdays.isEmpty ? parts.weekday == dueParts.weekday : weekdays.contains(parts.weekday ?? 0))
            case .monthly:
                weekdays.isEmpty
                    && distance(.month, to: day) % interval == 0
                    && (monthDays.isEmpty ? parts.day == dueParts.day : monthDays.contains(parts.day ?? 0))
            case .yearly:
                weekdays.isEmpty
                    && distance(.year, to: day) % interval == 0
                    && (months.isEmpty ? parts.month == dueParts.month : months.contains(parts.month ?? 0))
                    && (monthDays.isEmpty ? parts.day == dueParts.day : monthDays.contains(parts.day ?? 0))
            @unknown default:
                false
            }
            guard matches else { continue }
            if let end = rule.recurrenceEnd?.endDate, day > end { return nil }
            let time = calendar.dateComponents([.hour, .minute], from: due)
            return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day)
        }
        return nil
    }

    private static func sortedWeekdays(_ days: [EKRecurrenceDayOfWeek], calendar: Calendar) -> [EKRecurrenceDayOfWeek] {
        days.sorted {
            ($0.dayOfTheWeek.rawValue - calendar.firstWeekday + 7) % 7
                < ($1.dayOfTheWeek.rawValue - calendar.firstWeekday + 7) % 7
        }
    }

    private static func list(_ items: [String]) -> String {
        items.formatted(.list(type: .and))
    }

    private static func ordinalNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: n as NSNumber) ?? "\(n)"
    }

    private static func ordinalWord(_ n: Int) -> String {
        switch n {
        case -1: "last"
        case 1: "first"
        case 2: "second"
        case 3: "third"
        case 4: "fourth"
        case 5: "fifth"
        default: ordinalNumber(n)
        }
    }
}
