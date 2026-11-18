import SwiftData
import SwiftUI
import UserNotifications
import WidgetKit

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
        case .today: "sun.max"
        case .calendar: "calendar"
        case .reminders: "checkmark.rectangle.stack"
        case .notes: "doc.text"
        case .settings: "gearshape"
        }
    }

    /// Outline icon, as in Figma. iOS fills tab icons unless the variant is cleared on the image.
    var label: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .environment(\.symbolVariants, .none)
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
    /// How many open screens have their own Save button. While any do, the floating +
    /// steps aside. A count, so opening one note from another can't show it too early.
    @Entry var composerButtonHiders: Binding<Int> = .constant(0)
    /// The last deleted note, set by the screens that delete notes so a shake can bring it back.
    @Entry var lastDeletedNote: Binding<DeletedNote?> = .constant(nil)
}

/// What a shake offers to undo: the newest change to an event or reminder, or a deleted note.
enum PendingUndo {
    case item(UndoAction)
    case note(DeletedNote)

    var title: String {
        switch self {
        case .item(let action): action.title
        case .note: "Undo Delete Note"
        }
    }

    var message: String {
        switch self {
        case .item(let action): action.item.title
        case .note(let note): note.displayTitle
        }
    }
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
    @State private var composerButtonHiders = 0
    private var composerButtonHidden: Bool { composerButtonHiders > 0 }
    @State private var showingUndo = false
    @State private var pendingUndo: PendingUndo?
    @State private var lastDeletedNote: DeletedNote?
    @State private var openedFirstTab = false
    @AppStorage(AppTab.orderKey) private var tabOrder = ""
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query private var noteLinks: [NoteLink]

    private var noteLinkKeys: Set<String> {
        Set(noteLinks.filter { !$0.isNoteLink }.flatMap { [$0.externalID, $0.localID] }.filter { !$0.isEmpty })
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.order(from: tabOrder)) { tab in
                Tab(value: tab) {
                    screen(for: tab)
                } label: {
                    tab.label
                }
            }
            Tab(value: AppTab.settings) {
                SettingsView()
            } label: {
                AppTab.settings.label
            }
        }
        // iOS keeps some old tab icons when tabs swap places, even with the Tab API.
        // A new identity per order rebuilds the tab bar so every icon matches its title.
        .id(tabOrder)
        .tint(UD.brand600)
        .environment(eventKit)
        .environment(\.noteLinkKeys, noteLinkKeys)
        .environment(\.composerButtonHiders, $composerButtonHiders)
        .environment(\.lastDeletedNote, $lastDeletedNote)
        .overlay(alignment: .bottomTrailing) {
            // Hidden on Settings: nothing to add there, and it covered the last rows.
            if !composerButtonHidden && selectedTab != .settings
                && (eventKit.accessGranted || selectedTab == .notes) {
                Button {
                    composerRequest = ComposerRequest(
                        date: composerDate,
                        kind: composerKind
                    )
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .frame(width: 56, height: 56)
                        .background(UD.brand600, in: Circle())
                        .foregroundStyle(.white)
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
            guard !composerButtonHidden else { return }
            // Offer whichever happened last: a change to an item, or a deleted note.
            switch (eventKit.lastUndo, lastDeletedNote) {
            case let (action?, note?):
                pendingUndo = action.date > note.date ? .item(action) : .note(note)
            case let (action?, nil):
                pendingUndo = .item(action)
            case let (nil, note?):
                pendingUndo = .note(note)
            case (nil, nil):
                return
            }
            showingUndo = true
        }
        .alert(pendingUndo?.title ?? "Undo", isPresented: $showingUndo, presenting: pendingUndo) { pending in
            Button("Cancel", role: .cancel) {}
            Button("Undo") { undo(pending) }
        } message: { pending in
            Text(pending.message)
        }
        .task(id: eventKit.changeCount) {
            await eventKit.refreshAlerts()
            // Home and Lock Screen widgets read the same data, so refresh them too.
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onOpenURL { url in
            openWidgetLink(url)
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

    /// Handles taps on widgets. Links look like unifiedday://today.
    private func openWidgetLink(_ url: URL) {
        guard url.scheme == "unifiedday" else { return }
        switch url.host() {
        case "attention":
            selectedTab = .today
            eventKit.attentionRequested = true
        case "calendar":
            let seconds = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "day" }?.value.flatMap(Double.init)
            calendarDay = Calendar.current.startOfDay(for: seconds.map(Date.init(timeIntervalSince1970:)) ?? .now)
            selectedTab = .calendar
        case "new":
            composerRequest = ComposerRequest(date: .now, kind: .reminder)
        case "item":
            selectedTab = .today
            if let target = AlertTarget(url: url) {
                eventKit.open(target)
            }
        default:
            selectedTab = .today
        }
    }

    /// Undoes the last change. A deleted item comes back as a new copy, so its
    /// attached notes move over to the copy. A deleted note comes back as a new note.
    private func undo(_ pending: PendingUndo) {
        if case .note(let note) = pending {
            note.restore(in: modelContext)
            lastDeletedNote = nil
            modelContext.saveNotes(reportingTo: eventKit)
            return
        }
        guard let restored = eventKit.undo() else { return }
        for link in noteLinks where link.matches(restored.old) {
            link.externalID = restored.new.externalIdentifier
            link.localID = restored.new.storeIdentifier
        }
        modelContext.saveNotes(reportingTo: eventKit)
    }

    /// What + starts on: a note on Notes, an event on Calendar (which lists events
    /// only, so a new reminder would not show there), a reminder everywhere else.
    private var composerKind: ComposerView.DraftKind {
        switch selectedTab {
        case .notes: .note
        case .calendar: .event
        default: .reminder
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
