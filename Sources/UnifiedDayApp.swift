import SwiftUI

enum AppTab {
    case today, calendar, reminders, settings
}

/// One press of the + button, carrying the date the composer should start on.
struct ComposerRequest: Identifiable {
    let id = UUID()
    let date: Date
}

@main
struct UnifiedDayApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var eventKit = EventKitService()
    @State private var composerRequest: ComposerRequest?
    @State private var selectedTab = AppTab.today
    @State private var calendarDay = Calendar.current.startOfDay(for: .now)
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "calendar.day.timeline.left") }
                .tag(AppTab.today)
            CalendarView(selectedDay: $calendarDay)
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(AppTab.calendar)
            RemindersListView()
                .tabItem { Label("Reminders", systemImage: "checklist") }
                .tag(AppTab.reminders)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(AppTab.settings)
        }
        .environment(eventKit)
        .overlay(alignment: .bottomTrailing) {
            if eventKit.accessGranted {
                Button {
                    composerRequest = ComposerRequest(date: composerDate)
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .padding(18)
                        .background(.tint, in: Circle())
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
                .padding(.trailing)
                // Sits above the tab bar so the two never overlap.
                .padding(.bottom, 64)
                .accessibilityLabel("Add event or reminder")
            }
        }
        .overlay(alignment: .top) {
            if let message = eventKit.lastError {
                ErrorBanner(message: message) {
                    eventKit.lastError = nil
                }
            }
        }
        .animation(.default, value: eventKit.lastError)
        .sheet(item: $composerRequest) { request in
            ComposerView(initialDate: request.date)
                .environment(eventKit)
        }
        .task(id: eventKit.changeCount) {
            await eventKit.refreshAlerts()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                eventKit.refreshOnForeground()
            }
        }
    }

    /// New items start on the day selected in Calendar. Other days default to 9 AM.
    private var composerDate: Date {
        let calendar = Calendar.current
        guard selectedTab == .calendar, !calendar.isDateInToday(calendarDay) else { return .now }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: calendarDay) ?? calendarDay
    }
}

/// Non-blocking error message. Clears itself after a few seconds, or on tap.
struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.red, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .accessibilityHint("Dismisses this message")
        .transition(.move(edge: .top).combined(with: .opacity))
        .task(id: message) {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }
}
