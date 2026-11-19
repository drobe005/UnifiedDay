import SwiftUI

/// Permissions status, defaults, and the future home of integration connections
/// (Google, Zoom, Notion, Drive in v0.2).
struct SettingsView: View {
    @Environment(EventKitService.self) private var eventKit
    @AppStorage(EventKitService.badgeEnabledKey) private var badgeEnabled = false
    @AppStorage(EventKitService.defaultCalendarKey) private var defaultCalendarID = ""
    @AppStorage(EventKitService.defaultListKey) private var defaultListID = ""
    @AppStorage(EventKitService.alertsEnabledKey) private var alertsEnabled = false
    @AppStorage(EventKitService.eventAlertsKey) private var eventAlerts = true
    @AppStorage(EventKitService.taskAlertsKey) private var taskAlerts = true
    @AppStorage(EventKitService.alertLeadMinutesKey) private var alertLeadMinutes = EventKitService.defaultAlertLeadMinutes

    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system
    @State private var bannersOn: Bool?
    @State private var showingFeedbackAddress = false

    private let alertLeadOptions = [0, 5, 10, 15, 30, 60]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: UD.sectionSpacing) {
                    sections
                }
                .padding(.horizontal, UD.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .udScreenBackground()
            .navigationTitle("Settings")
            .alert("No email app set up", isPresented: $showingFeedbackAddress) {
                Button("Copy Address") { UIPasteboard.general.string = Feedback.address }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Send your feedback to \(Feedback.address).")
            }
        }
    }

    @ViewBuilder
    private var sections: some View {
                UDSection(title: "Appearance") {
                    menuRow("Theme", value: appearance.label) {
                        Picker("Theme", selection: $appearance) {
                            ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
                        }
                    }
                }

                UDSection(title: "Access") {
                    UDRow(title: "Calendar and Reminders") {
                        UDValue(text: eventKit.accessGranted ? "Granted" : "Not granted")
                    }
                    .accessibilityElement(children: .combine)
                    if !eventKit.accessGranted {
                        UDDivider()
                        linkRow("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }

                if eventKit.accessGranted {
                    UDSection(title: "Defaults") {
                        menuRow("Calendar", value: calendarName) {
                            Picker("Calendar", selection: $defaultCalendarID) {
                                Text("Apple default").tag("")
                                ForEach(eventKit.writableEventCalendars(), id: \.calendarIdentifier) { calendar in
                                    Text(calendar.title).tag(calendar.calendarIdentifier)
                                }
                            }
                        }
                        UDDivider()
                        menuRow("Task list", value: listName) {
                            Picker("Task list", selection: $defaultListID) {
                                Text("Apple default").tag("")
                                ForEach(eventKit.writableReminderLists(), id: \.calendarIdentifier) { list in
                                    Text(list.title).tag(list.calendarIdentifier)
                                }
                            }
                        }
                    }

                    UDSection(
                        title: "Alerts",
                        footer: "Choose what alerts you. Tasks with no time alert at 9 AM. All-day events don't alert. Changes apply when you open the app."
                    ) {
                        toggleRow("Alerts", isOn: $alertsEnabled)
                        if alertsEnabled {
                            UDDivider()
                            toggleRow("Events", isOn: $eventAlerts)
                            if eventAlerts {
                                UDDivider()
                                menuRow("Event alert", value: alertLeadLabel(alertLeadMinutes)) {
                                    Picker("Event alert", selection: $alertLeadMinutes) {
                                        ForEach(alertLeadOptions, id: \.self) { minutes in
                                            Text(alertLeadLabel(minutes)).tag(minutes)
                                        }
                                    }
                                }
                            }
                            UDDivider()
                            toggleRow("Tasks", isOn: $taskAlerts)
                        }
                        // Stays visible with Alerts off, since iOS Settings may be the fix.
                        if let bannersOn {
                            UDDivider()
                            UDRow(title: "Banners") { UDValue(text: bannersOn ? "On" : "Off") }
                                .accessibilityElement(children: .combine)
                        }
                        UDDivider()
                        linkRow("Change in iOS Settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
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
                    .onChange(of: eventAlerts) {
                        Task { await eventKit.refreshAlerts() }
                    }
                    .onChange(of: taskAlerts) {
                        Task { await eventKit.refreshAlerts() }
                    }

                    UDSection(
                        title: "Badge",
                        footer: "Shows tasks due today plus overdue. Updates when you open the app."
                    ) {
                        toggleRow("App icon badge", isOn: $badgeEnabled)
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

                UDSection(title: "Tabs") {
                    NavigationLink {
                        TabOrderView()
                    } label: {
                        UDRow(title: "Tab Order", showsChevron: true)
                    }
                    .buttonStyle(UDRowButtonStyle())
                }

                UDSection(title: "Help") {
                    NavigationLink {
                        ScrollView {
                            SymbolKeyView()
                                .padding(.horizontal, UD.screenPadding)
                                .padding(.vertical, 16)
                        }
                        .udScreenBackground()
                        .navigationTitle("How to Read Your Day")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        UDRow(title: "How to Read Your Day", showsChevron: true)
                    }
                    .buttonStyle(UDRowButtonStyle())
                }

                UDSection(title: "Integrations") {
                    integrationRow(name: "Google", detail: "Meet links and Drive attachments", comingSoon: true)
                    UDDivider()
                    integrationRow(name: "Zoom", detail: "Create and join meetings", comingSoon: true)
                    UDDivider()
                    integrationRow(name: "Notion", detail: "Two-way task sync", comingSoon: true)
                }

                UDSection(
                    title: "About",
                    footer: "Report a bug or share an idea. Your app version and iPhone model are added to the email for you."
                ) {
                    linkRow("Send Feedback") { sendFeedback() }
                    UDDivider()
                    UDRow(title: "Version") { UDValue(text: Feedback.appVersion) }
                        .accessibilityElement(children: .combine)
                }
    }

    private var calendarName: String {
        eventKit.writableEventCalendars().first { $0.calendarIdentifier == defaultCalendarID }?.title ?? "Apple default"
    }

    private var listName: String {
        eventKit.writableReminderLists().first { $0.calendarIdentifier == defaultListID }?.title ?? "Apple default"
    }

    /// A row that opens a menu of choices, showing the current choice on the right.
    private func menuRow(_ title: String, value: String, @ViewBuilder picker: () -> some View) -> some View {
        Menu {
            picker()
        } label: {
            UDRow(title: title) {
                UDValue(text: value)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(UD.textQuaternary)
            }
        }
        .buttonStyle(UDRowButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        UDRow(title: title) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(UD.brand600)
        }
    }

    /// A brand text row that performs an action.
    private func linkRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(UD.brand700)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(UDRowButtonStyle())
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
        UDRow(title: name, subtitle: detail) {
            if comingSoon {
                UDValue(text: "v0.2")
            }
        }
        .accessibilityElement(children: .combine)
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
                    Text(tab.title)
                        .font(.body)
                        .foregroundStyle(UD.textPrimary)
                }
                .onMove { from, to in
                    order.move(fromOffsets: from, toOffset: to)
                }
            } header: {
                UDFormGap()
            }
            .udFormRow()
            Section {
                Button("Reset to Default") { order = AppTab.movable }
                    .font(.body.weight(.medium))
                    .foregroundStyle(order == AppTab.movable ? UD.textQuaternary : UD.brand700)
                    .disabled(order == AppTab.movable)
            } header: {
                // The explanation is this section's heading, so no line is drawn around it.
                UDFormFooter(text: "Drag to reorder. The tab bar updates when you go back. The app opens on the first tab, and Settings always stays last.")
                    .textCase(nil)
                    .padding(.top, 10)
                    .listRowInsets(UD.rowInsets)
            }
            .udFormRow()
            .listRowSeparator(.hidden)
        }
        .udFormBackground()
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Tab Order")
        .onAppear { order = AppTab.order(from: saved) }
        .onDisappear {
            let value = order == AppTab.movable ? "" : order.map(\.rawValue).joined(separator: ",")
            if value != saved { saved = value }
        }
    }
}
