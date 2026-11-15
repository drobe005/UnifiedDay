import SwiftUI
import WidgetKit

@main
struct UnifiedDayWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        AttentionWidget()
        MonthWidget()
        DayProgressWidget()
    }
}

// MARK: - Today

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Today", provider: DayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("What's next and what's left today.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    let entry: DayEntry
    @Environment(\.widgetFamily) private var family

    private var data: DayData { entry.data }
    private var next: WidgetItem? { data.upNext(at: entry.date) }
    private var rest: [WidgetItem] { data.remaining(at: entry.date, excluding: next) }

    var body: some View {
        Group {
            if !data.accessGranted {
                NeedsAccessView()
            } else {
                switch family {
                case .systemMedium: medium
                case .systemLarge: large
                case .accessoryRectangular: rectangular
                case .accessoryInline: inline
                default: small
                }
            }
        }
        .widgetURL(family == .systemSmall || family.isAccessory ? (next?.url ?? DeepLink.today) : DeepLink.today)
        .widgetBackground(family)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(date: entry.date)
            Spacer(minLength: 6)
            if let next {
                UpNextBlock(item: next, date: entry.date)
            } else {
                NothingNext()
            }
            Spacer(minLength: 6)
            if !rest.isEmpty {
                Text("+ \(rest.count) more today")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WC.text3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(date: entry.date, showsAdd: true)
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let next {
                        Link(destination: next.url) {
                            UpNextBlock(item: next, date: entry.date, titleSize: 15)
                        }
                    } else {
                        NothingNext()
                    }
                }
                .frame(width: 130, alignment: .leading)
                Rectangle()
                    .fill(WC.border)
                    .frame(width: 1)
                VStack(alignment: .leading, spacing: 9) {
                    if rest.isEmpty {
                        Text("Nothing else today")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(WC.text3)
                    }
                    // Times are off in this size so titles have room, as in the Figma design.
                    ForEach(rest.prefix(3)) { item in
                        WidgetRow(item: item, showsTime: false)
                    }
                    if rest.count > 3 {
                        Text("+ \(rest.count - 3) more")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WC.text3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var large: some View {
        let overdue = rest.filter(\.isOverdue)
        let later = rest.filter { !$0.isOverdue }
        let overdueShown = Array(overdue.prefix(2))
        let laterShown = Array(later.prefix(max(0, 6 - overdueShown.count)))
        let hidden = rest.count - overdueShown.count - laterShown.count
        return VStack(alignment: .leading, spacing: 12) {
            WidgetHeader(date: entry.date, showsAdd: true)
            Group {
                if let next {
                    Link(destination: next.url) {
                        UpNextBlock(item: next, date: entry.date, titleSize: 17)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    NothingNext()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(WC.brand50, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(WC.brand100))

            if !overdueShown.isEmpty {
                section("Overdue", color: WC.error, items: overdueShown)
            }
            if !laterShown.isEmpty {
                section("Later today", color: WC.text3, items: laterShown)
            }
            Spacer(minLength: 0)
            if hidden > 0 {
                Text("+ \(hidden) more today")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WC.text3)
            }
        }
    }

    private func section(_ title: String, color: Color, items: [WidgetItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            ForEach(items) { item in
                WidgetRow(item: item)
            }
        }
    }

    private var rectangular: some View {
        Group {
            if let next {
                HStack(alignment: .top, spacing: 6) {
                    RoundedRectangle(cornerRadius: 1)
                        .frame(width: 3)
                        .widgetAccentable()
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Up next · \(WidgetFormat.relative(next, at: entry.date))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .widgetAccentable()
                        Text(next.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Text(WidgetFormat.detail(next))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(WidgetFormat.shortDay(entry.date))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Nothing else today")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Label {
            if let next {
                let time = next.start.map { $0.formatted(.dateTime.hour().minute()) } ?? ""
                Text("\(WidgetFormat.shortDay(entry.date)) · \(next.title) \(time)")
            } else {
                Text("\(WidgetFormat.shortDay(entry.date)) · Nothing else today")
            }
        } icon: {
            Image(systemName: "calendar")
        }
    }
}

// MARK: - Needs attention

struct AttentionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NeedsAttention", provider: DayProvider()) { entry in
            AttentionWidgetView(entry: entry)
        }
        .configurationDisplayName("Needs Attention")
        .description("Reminders that are overdue or due today.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct AttentionWidgetView: View {
    let entry: DayEntry
    @Environment(\.widgetFamily) private var family

    private var data: DayData { entry.data }

    var body: some View {
        Group {
            if !data.accessGranted {
                NeedsAccessView()
            } else if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: -2) {
                        Text("\(data.reminders.count)")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                        Text("DUE")
                            .font(.system(size: 9, weight: .semibold))
                            .widgetAccentable()
                    }
                }
                .accessibilityLabel("\(data.reminders.count) reminders due")
            } else {
                small
            }
        }
        .widgetURL(DeepLink.attention)
        .widgetBackground(family)
    }

    private var small: some View {
        let count = data.reminders.count
        let top = data.overdue.first ?? data.dueToday.first
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(WC.orange500).frame(width: 8, height: 8)
                Text("Needs attention")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WC.orange700)
                    .lineLimit(1)
            }
            .widgetAccentable()
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(count)")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(WC.text1)
                Text(count == 1 ? "reminder" : "reminders")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WC.text2)
            }
            if count == 0 {
                Text("All clear for today.")
                    .font(.system(size: 12))
                    .foregroundStyle(WC.text3)
            } else {
                (Text("\(data.overdue.count) overdue").foregroundStyle(data.overdue.isEmpty ? WC.text3 : WC.error)
                    + Text(" · \(data.dueToday.count) due today").foregroundStyle(WC.text3))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            if let top {
                HStack(spacing: 6) {
                    Circle()
                        .strokeBorder(top.isOverdue ? WC.error : WC.text4, lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                    Text(top.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WC.text1)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Month

struct MonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Month", provider: DayProvider()) { entry in
            MonthWidgetView(entry: entry)
        }
        .configurationDisplayName("Month")
        .description("This month at a glance, with dots on busy days.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MonthWidgetView: View {
    let entry: DayEntry
    @Environment(\.widgetFamily) private var family

    private var data: DayData { entry.data }

    var body: some View {
        Group {
            if !data.accessGranted {
                NeedsAccessView()
            } else if family == .systemMedium {
                medium
            } else {
                small
            }
        }
        .widgetURL(DeepLink.calendar(Calendar.current.startOfDay(for: entry.date)))
        .widgetBackground(family)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.date.formatted(.dateTime.month(.wide)))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WC.brand700)
                .widgetAccentable()
            MiniMonth(date: entry.date, marked: data.markedDays)
            Spacer(minLength: 0)
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.date.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WC.brand700)
                    .widgetAccentable()
                Text(entry.date.formatted(.dateTime.day()))
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(WC.text1)
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 3) {
                    stat(data.events.count, "event", "events", WC.text2)
                    stat(data.reminders.count, "reminder", "reminders", WC.text2)
                    stat(data.overdue.count, "overdue", "overdue", data.overdue.isEmpty ? WC.text3 : WC.error)
                }
            }
            .frame(width: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.date.formatted(.dateTime.month(.wide)))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WC.text2)
                MiniMonth(date: entry.date, marked: data.markedDays, cellHeight: 15, fontSize: 10, linksDays: true)
                Spacer(minLength: 0)
            }
        }
    }

    private func stat(_ count: Int, _ one: String, _ many: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WC.text1)
            Text(count == 1 ? one : many)
                .font(.system(size: 12))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Day progress (Lock Screen)

struct DayProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DayProgress", provider: DayProvider()) { entry in
            DayProgressView(entry: entry)
        }
        .configurationDisplayName("Day Progress")
        .description("Events left today, with a ring for how far through the day you are.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct DayProgressView: View {
    let entry: DayEntry

    /// How far through 7 AM to 10 PM the entry's time is.
    private var progress: Double {
        let calendar = Calendar.current
        guard let start = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: entry.date),
              let end = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: entry.date) else { return 0 }
        return min(1, max(0, entry.date.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }

    private var eventsLeft: Int {
        entry.data.events.filter { ($0.end ?? $0.start ?? .distantPast) > entry.date }.count
    }

    var body: some View {
        Group {
            if !entry.data.accessGranted {
                NeedsAccessView()
            } else {
                Gauge(value: progress) {
                    Text("Day")
                } currentValueLabel: {
                    VStack(spacing: -2) {
                        Text("\(eventsLeft)")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                        Text("LEFT")
                            .font(.system(size: 8, weight: .semibold))
                    }
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
                .accessibilityLabel("\(eventsLeft) events left today")
            }
        }
        .widgetURL(DeepLink.today)
        .widgetBackground(.accessoryCircular)
    }
}

extension WidgetFamily {
    var isAccessory: Bool {
        self == .accessoryCircular || self == .accessoryInline || self == .accessoryRectangular
    }
}

// MARK: - Previews

#Preview("Today small", as: .systemSmall) { TodayWidget() } timeline: { DayEntry(date: .now, data: .preview) }
#Preview("Today medium", as: .systemMedium) { TodayWidget() } timeline: { DayEntry(date: .now, data: .preview) }
#Preview("Today large", as: .systemLarge) { TodayWidget() } timeline: { DayEntry(date: .now, data: .preview) }
#Preview("Attention", as: .systemSmall) { AttentionWidget() } timeline: { DayEntry(date: .now, data: .preview) }
#Preview("Month", as: .systemMedium) { MonthWidget() } timeline: { DayEntry(date: .now, data: .preview) }
