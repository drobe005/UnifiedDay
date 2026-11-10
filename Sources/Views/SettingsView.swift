import SwiftUI

/// Permissions status, defaults, and the future home of integration connections
/// (Google, Zoom, Notion, Drive in v0.2).
struct SettingsView: View {
    @Environment(EventKitService.self) private var eventKit
    @AppStorage(EventKitService.badgeEnabledKey) private var badgeEnabled = false
    @AppStorage(EventKitService.defaultCalendarKey) private var defaultCalendarID = ""
    @AppStorage(EventKitService.defaultListKey) private var defaultListID = ""
    @AppStorage(EventKitService.alertsEnabledKey) private var alertsEnabled = false
    @AppStorage(EventKitService.alertLeadMinutesKey) private var alertLeadMinutes = EventKitService.defaultAlertLeadMinutes

    @State private var bannersOn: Bool?
    @State private var showingFeedbackAddress = false

    private let alertLeadOptions = [0, 5, 10, 15, 30, 60]

    var body: some View {
        NavigationStack {
            Form {
                Section("Access") {
                    HStack {
                        Label("Calendar and Reminders", systemImage: "calendar.badge.checkmark")
                        Spacer()
                        Text(eventKit.accessGranted ? "Granted" : "Not granted")
                            .foregroundStyle(eventKit.accessGranted ? .green : .orange)
                    }
                    if !eventKit.accessGranted {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }

                if eventKit.accessGranted {
                    Section("Defaults") {
                        Picker("Calendar", selection: $defaultCalendarID) {
                            Text("Apple default").tag("")
                            ForEach(eventKit.writableEventCalendars(), id: \.calendarIdentifier) { calendar in
                                Text(calendar.title).tag(calendar.calendarIdentifier)
                            }
                        }
                        Picker("Reminders list", selection: $defaultListID) {
                            Text("Apple default").tag("")
                            ForEach(eventKit.writableReminderLists(), id: \.calendarIdentifier) { list in
                                Text(list.title).tag(list.calendarIdentifier)
                            }
                        }
                    }

                    Section {
                        Toggle("Alerts", isOn: $alertsEnabled)
                        if alertsEnabled {
                            Picker("Event alert", selection: $alertLeadMinutes) {
                                ForEach(alertLeadOptions, id: \.self) { minutes in
                                    Text(alertLeadLabel(minutes)).tag(minutes)
                                }
                            }
                        }
                        // Stays visible with Alerts off, since iOS Settings may be the fix.
                        if let bannersOn {
                            LabeledContent("Banners", value: bannersOn ? "On" : "Off")
                        }
                        Button("Change in iOS Settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    } footer: {
                        Text("Covers timed events and reminders. Reminders with no time alert at 9 AM. Changes apply when you open the app.")
                    }
                    .onChange(of: alertsEnabled) { _, enabled in
                        Task {
                            if enabled, !(await eventKit.enableAlerts()) {
                                alertsEnabled = false
                            }
                            await eventKit.refreshAlerts()
                            bannersOn = await eventKit.bannersAllowed()
                        }
                    }
                    // changeCount also bumps on return from iOS Settings.
                    .task(id: eventKit.changeCount) {
                        bannersOn = await eventKit.bannersAllowed()
                    }
                    .onChange(of: alertLeadMinutes) {
                        Task { await eventKit.refreshAlerts() }
                    }

                    Section {
                        Toggle("App icon badge", isOn: $badgeEnabled)
                    } footer: {
                        Text("Shows reminders due today plus overdue. Updates when you open the app.")
                    }
                    .onChange(of: badgeEnabled) { _, enabled in
                        Task {
                            if enabled, !(await eventKit.enableBadge()) {
                                badgeEnabled = false
                            }
                            await eventKit.refreshBadge()
                        }
                    }
                }

                Section("Tabs") {
                    NavigationLink("Tab Order") {
                        TabOrderView()
                    }
                }

                Section("Integrations") {
                    integrationRow(name: "Google", detail: "Meet links and Drive attachments", comingSoon: true)
                    integrationRow(name: "Zoom", detail: "Create and join meetings", comingSoon: true)
                    integrationRow(name: "Notion", detail: "Two-way task sync", comingSoon: true)
                }

                Section {
                    Button {
                        sendFeedback()
                    } label: {
                        Label("Send Feedback", systemImage: "envelope")
                    }
                    LabeledContent("Version", value: Feedback.appVersion)
                } header: {
                    Text("About")
                } footer: {
                    Text("Report a bug or share an idea. Your app version and iPhone model are added to the email for you.")
                }
            }
            .navigationTitle("Settings")
            .alert("No email app set up", isPresented: $showingFeedbackAddress) {
                Button("Copy Address") { UIPasteboard.general.string = Feedback.address }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Send your feedback to \(Feedback.address).")
            }
        }
    }

    /// Opens the person's default email app with a filled-in draft. If no email
    /// app can open it, shows the address instead so feedback is never lost.
    private func sendFeedback() {
        guard let url = Feedback.mailURL() else {
            showingFeedbackAddress = true
            return
        }
        UIApplication.shared.open(url) { opened in
            if !opened { showingFeedbackAddress = true }
        }
    }

    private func alertLeadLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: "At start time"
        case 60: "1 hour before"
        default: "\(minutes) minutes before"
        }
    }

    private func integrationRow(name: String, detail: String, comingSoon: Bool) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if comingSoon {
                Text("v0.2")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Reorders the tabs at the bottom. Settings always stays last.
struct TabOrderView: View {
    @AppStorage(AppTab.orderKey) private var saved = ""
    /// Edits stay here until you leave the screen. Saving rebuilds the tab bar,
    /// which would cancel a drag and close this screen if it happened mid-edit.
    @State private var order: [AppTab] = []

    var body: some View {
        List {
            Section {
                ForEach(order) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                }
                .onMove { from, to in
                    order.move(fromOffsets: from, toOffset: to)
                }
            } footer: {
                Text("Drag to reorder. The tab bar updates when you go back. The app opens on the first tab, and Settings always stays last.")
            }
            Section {
                Button("Reset to Default") { order = AppTab.movable }
                    .disabled(order == AppTab.movable)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Tab Order")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { order = AppTab.order(from: saved) }
        .onDisappear {
            let value = order == AppTab.movable ? "" : order.map(\.rawValue).joined(separator: ",")
            if value != saved { saved = value }
        }
    }
}
