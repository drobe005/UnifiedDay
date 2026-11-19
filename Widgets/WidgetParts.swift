import AppIntents
import SwiftUI
import WidgetKit

/// Colors from the widget's asset catalog, copied from the app's "UnifiedDay" set.
enum WC {
    static let bgCard = Color("BgCard")
    static let bgSubtle = Color("BgSubtle")
    static let bgSecondary = Color("BgSecondary")
    static let border = Color("BorderSecondary")
    static let brand50 = Color("Brand50")
    static let brand100 = Color("Brand100")
    static let brand200 = Color("Brand200")
    static let brand600 = Color("Brand600")
    static let brand700 = Color("Brand700")
    static let error = Color("ErrorFg")
    static let orange100 = Color("Orange100")
    static let orange500 = Color("Orange500")
    static let orange700 = Color("Orange700")
    static let text1 = Color("TextPrimary")
    static let text2 = Color("TextSecondary")
    static let text3 = Color("TextTertiary")
    static let text4 = Color("TextQuaternary")
}

enum WidgetFormat {
    /// "Mon 9"
    static func shortDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day())
    }

    /// "Now", "in 19m", "in 2h", "in 1h 20m".
    static func relative(_ item: WidgetItem, at date: Date) -> String {
        guard let start = item.start else { return "Today" }
        if start <= date { return "Now" }
        let minutes = Int((start.timeIntervalSince(date) / 60).rounded(.up))
        if minutes < 60 { return "in \(minutes)m" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "in \(hours)h" : "in \(hours)h \(rest)m"
    }

    /// "10:00 AM · Work"
    static func detail(_ item: WidgetItem) -> String {
        [item.isAllDay ? "All day" : item.timeLabel, item.sourceName]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// Right side of a row: a time, "All day", or how late an overdue reminder is.
    static func rowTime(_ item: WidgetItem) -> String? {
        if item.isOverdue, let start = item.start {
            return Calendar.current.isDateInYesterday(start)
                ? "Yesterday"
                : start.formatted(.dateTime.month(.abbreviated).day())
        }
        if item.isAllDay { return "All day" }
        return item.timeLabel
    }
}

/// "Mon 9" with an optional + that opens the composer.
struct WidgetHeader: View {
    let date: Date
    var showsAdd = false

    var body: some View {
        HStack {
            Text(WidgetFormat.shortDay(date))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WC.text1)
            Spacer(minLength: 4)
            if showsAdd {
                Link(destination: DeepLink.new) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WC.brand700)
                        .frame(width: 26, height: 26)
                        .background(WC.brand50, in: Circle())
                        .overlay(Circle().strokeBorder(WC.brand200))
                        .widgetAccentable()
                }
                .accessibilityLabel("Add event or task")
            }
        }
    }
}

struct WidgetPill: View {
    enum Style { case brand, gray }
    let text: String
    let style: Style

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(style == .brand ? WC.brand700 : WC.text2)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(style == .brand ? WC.brand50 : WC.bgSecondary, in: Capsule())
            .overlay(Capsule().strokeBorder(style == .brand ? WC.brand200 : WC.border))
    }
}

/// The calendar-color bar with the title and "10:00 AM · Work".
struct UpNextBlock: View {
    let item: WidgetItem
    let date: Date
    var titleSize: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                WidgetPill(text: "Up next", style: .brand)
                WidgetPill(text: WidgetFormat.relative(item, at: date), style: .gray)
            }
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(item.color)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: titleSize, weight: .semibold))
                        .foregroundStyle(WC.text1)
                        .lineLimit(2)
                    Text(WidgetFormat.detail(item))
                        .font(.system(size: 12))
                        .foregroundStyle(WC.text3)
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Shown when nothing timed is left today.
struct NothingNext: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(WC.brand600)
                .widgetAccentable()
            Text("Nothing else today")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WC.text1)
            Text("Enjoy the rest of your day.")
                .font(.system(size: 12))
                .foregroundStyle(WC.text3)
        }
    }
}

/// One line in a list: a check circle for reminders, a colored dot for events.
struct WidgetRow: View {
    let item: WidgetItem
    var showsTime = true

    var body: some View {
        HStack(spacing: 8) {
            leading
                .frame(width: 18, height: 18)
            Link(destination: item.url) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WC.text1)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if showsTime, let time = WidgetFormat.rowTime(item) {
                        Text(time)
                            .font(.system(size: 12))
                            .foregroundStyle(item.isOverdue ? WC.error : WC.text3)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var leading: some View {
        if item.kind == .reminder {
            Button(intent: CompleteReminderIntent(reminderID: item.storeID)) {
                Circle()
                    .strokeBorder(item.isOverdue ? WC.error : WC.text4, lineWidth: 1.5)
                    .frame(width: 17, height: 17)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(item.title)")
        } else {
            Circle()
                .fill(item.color)
                .frame(width: 8, height: 8)
        }
    }
}

/// The month grid: today filled, a dot under days with items.
struct MiniMonth: View {
    let date: Date
    let marked: Set<Int>
    var cellHeight: CGFloat = 15
    var fontSize: CGFloat = 10
    var linksDays = false

    private var calendar: Calendar { .current }

    var body: some View {
        let days = monthDays
        let today = calendar.component(.day, from: date)
        Grid(horizontalSpacing: 0, verticalSpacing: 1) {
            GridRow {
                ForEach(Array(weekdayLetters.enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(.system(size: fontSize - 1, weight: .medium))
                        .foregroundStyle(WC.text4)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<(days.count / 7), id: \.self) { week in
                GridRow {
                    ForEach(0..<7, id: \.self) { column in
                        cell(days[week * 7 + column], today: today)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ day: Int?, today: Int) -> some View {
        if let day {
            let isToday = day == today
            let label = Text("\(day)")
                .font(.system(size: fontSize, weight: isToday ? .bold : .medium))
                .foregroundStyle(isToday ? Color.white : WC.text2)
                .frame(width: cellHeight + 2, height: cellHeight)
                .background {
                    if isToday {
                        Circle().fill(WC.brand600).frame(width: cellHeight + 2, height: cellHeight + 2)
                            .widgetAccentable()
                    }
                }
                .overlay(alignment: .bottom) {
                    if marked.contains(day) && !isToday {
                        Circle().fill(WC.brand600).frame(width: 3, height: 3).offset(y: 3)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 2)
            if linksDays, let link = dayDate(day) {
                Link(destination: DeepLink.calendar(link)) { label }
            } else {
                label
            }
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: cellHeight)
        }
    }

    private func dayDate(_ day: Int) -> Date? {
        var parts = calendar.dateComponents([.year, .month], from: date)
        parts.day = day
        return calendar.date(from: parts)
    }

    /// "S M T W T F S", starting on the user's first weekday.
    private var weekdayLetters: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Day numbers padded with nil so the count is a multiple of 7.
    private var monthDays: [Int?] {
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let range = calendar.range(of: .day, in: .month, for: date) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        var days: [Int?] = Array(repeating: nil, count: lead) + range.map { Optional($0) }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }
}

/// Shown until calendar and reminders access is granted in the app.
struct NeedsAccessView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Open UnifiedDay", systemImage: "calendar")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "calendar")
                    .font(.system(size: 20, weight: .semibold))
            }
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("UnifiedDay").font(.headline)
                Text("Open the app to show your day.").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(WC.brand600)
                Spacer(minLength: 0)
                Text("Open UnifiedDay to show your day.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WC.text1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

extension View {
    /// Card background for Home Screen widgets, clear on the Lock Screen.
    func widgetBackground(_ family: WidgetFamily) -> some View {
        containerBackground(for: .widget) {
            switch family {
            case .accessoryCircular, .accessoryInline, .accessoryRectangular: Color.clear
            default: WC.bgCard
            }
        }
    }
}
