import SwiftData
import SwiftUI
import UserNotifications

enum AppTab: String, CaseIterable, Identifiable {
    case today, calendar, reminders, notes, settings

    /// UserDefaults key for the order set in Settings, saved as comma-separated names.
    static let orderKey = "tabOrder"
    /// Tabs that can be reordered. Settings always stays last.
    static let movable: [AppTab] = [.today, .calendar, .reminders, .notes]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .notes: "Notes"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "calendar.day.timeline.left"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .notes: "note.text"
        case .settings: "gear"
        }
    }

    /// The saved order, with any tab it's missing added at the end.
    static func order(from saved: String) -> [AppTab] {
        var order: [AppTab] = []
        for name in saved.split(separator: ",") {
            if let tab = AppTab(rawValue: String(name)), movable.contains(tab), !order.contains(tab) {
                order.append(tab)
            }
        }
        return order + movable.filter { !order.contains($0) }
    }
}

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

extension UIWindow {
    /// SwiftUI has no shake gesture, so the window passes shakes on for undo.
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
    }
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

    init() {
        // Set before launch finishes, so iOS hands over an alert tap that opened the app.
        UNUserNotificationCenter.current().delegate = EventKitService.alertPresenter
        UD.configureAppearance()
    }

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
    @State private var showingUndo = false
    @State private var openedFirstTab = false
    @AppStorage(AppTab.orderKey) private var tabOrder = ""
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query private var noteLinks: [NoteLink]

    private var noteLinkKeys: Set<String> {
        Set(noteLinks.flatMap { [$0.externalID, $0.localID] }.filter { !$0.isEmpty })
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.order(from: tabOrder)) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    screen(for: tab)
                }
            }
            Tab(AppTab.settings.title, systemImage: AppTab.settings.systemImage, value: AppTab.settings) {
                SettingsView()
            }
        }
        // iOS keeps some old tab icons when tabs swap places, even with the Tab API.
        // A new identity per order rebuilds the tab bar so every icon matches its title.
        .id(tabOrder)
        .tint(UD.brand600)
        .environment(eventKit)
        .environment(\.noteLinkKeys, noteLinkKeys)
        .environment(\.composerButtonHidden, $composerButtonHidden)
        .overlay(alignment: .bottomTrailing) {
            // Hidden on Settings: nothing to add there, and it covered the last rows.
            if !composerButtonHidden && selectedTab != .settings
                && (eventKit.accessGranted || selectedTab == .notes) {
                Button {
                    composerRequest = ComposerRequest(
                        date: composerDate,
                        kind: selectedTab == .notes ? .note : .reminder
                    )
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .frame(width: 56, height: 56)
                        .background(UD.brand600, in: Circle())
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 8)
                        .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
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
        .sheet(item: $eventKit.alertItemToOpen) { item in
            ItemDetailView(item: item) {}
                .environment(eventKit)
        }
        .sheet(item: $composerRequest) { request in
            ComposerView(initialDate: request.date, initialKind: request.kind)
                .environment(eventKit)
        }
        .task {
            if let storageError {
                eventKit.lastError = storageError
            }
            // The app opens on the first tab in the order chosen in Settings.
            if !openedFirstTab {
                openedFirstTab = true
                selectedTab = AppTab.order(from: tabOrder).first ?? .today
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            // The note editor keeps iOS's own text undo, so shakes there are left alone.
            guard eventKit.lastUndo != nil, !composerButtonHidden else { return }
            showingUndo = true
        }
        .alert(eventKit.lastUndo?.title ?? "Undo", isPresented: $showingUndo, presenting: eventKit.lastUndo) { _ in
            Button("Cancel", role: .cancel) {}
            Button("Undo") { undo() }
        } message: { action in
            Text(action.item.title)
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

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .today: TodayView()
        case .calendar: CalendarView(selectedDay: $calendarDay)
        case .reminders: RemindersListView()
        case .notes: NotesListView()
        case .settings: SettingsView()
        }
    }

    /// Undoes the last change. A deleted item comes back as a new copy, so its
    /// attached notes move over to the copy.
    private func undo() {
        guard let restored = eventKit.undo() else { return }
        for link in noteLinks where link.matches(restored.old) {
            link.externalID = restored.new.externalIdentifier
            link.localID = restored.new.storeIdentifier
        }
        modelContext.saveNotes(reportingTo: eventKit)
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
                .font(.subheadline.weight(.medium))
                .foregroundStyle(UD.errorFg)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(UD.errorBg, in: RoundedRectangle(cornerRadius: UD.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: UD.cardRadius, style: .continuous)
                        .strokeBorder(UD.errorBorder)
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
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
