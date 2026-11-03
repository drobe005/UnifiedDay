import SwiftData
import SwiftUI

enum AppTab {
    case today, calendar, reminders, notes, settings
}

/// One press of the + button, carrying what the composer should start on.
struct ComposerRequest: Identifiable {
    let id = UUID()
    let date: Date
    let kind: ComposerView.DraftKind
}

extension EnvironmentValues {
    /// Identifiers of items with attached notes, for the marker on timeline rows.
    @Entry var noteLinkKeys: Set<String> = []
    /// Set by screens that have their own Save button, so the floating + steps aside.
    @Entry var composerButtonHidden: Binding<Bool> = .constant(false)
}

@main
struct UnifiedDayApp: App {
    private let storage = NoteStorage.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView(storageError: storage.error)
        }
        .modelContainer(storage.container)
    }
}

struct RootView: View {
    let storageError: String?

    @State private var eventKit = EventKitService()
    @State private var composerRequest: ComposerRequest?
    @State private var selectedTab = AppTab.today
    @State private var calendarDay = Calendar.current.startOfDay(for: .now)
    @State private var composerButtonHidden = false
    @Environment(\.scenePhase) private var scenePhase
    @Query private var noteLinks: [NoteLink]

    private var noteLinkKeys: Set<String> {
        Set(noteLinks.flatMap { [$0.externalID, $0.localID] }.filter { !$0.isEmpty })
    }

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
            NotesListView()
                .tabItem { Label("Notes", systemImage: "note.text") }
                .tag(AppTab.notes)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(AppTab.settings)
        }
        .environment(eventKit)
        .environment(\.noteLinkKeys, noteLinkKeys)
        .environment(\.composerButtonHidden, $composerButtonHidden)
        .overlay(alignment: .bottomTrailing) {
            if !composerButtonHidden && (eventKit.accessGranted || selectedTab == .notes) {
                Button {
                    composerRequest = ComposerRequest(
                        date: composerDate,
                        kind: selectedTab == .notes ? .note : .reminder
                    )
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
                .accessibilityLabel("Add event, reminder, or note")
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
            ComposerView(initialDate: request.date, initialKind: request.kind)
                .environment(eventKit)
        }
        .task {
            if let storageError {
                eventKit.lastError = storageError
            }
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
