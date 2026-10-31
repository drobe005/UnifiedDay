import SwiftUI

/// Permissions status, defaults, and the future home of integration connections
/// (Google, Zoom, Notion, Drive in v0.2).
struct SettingsView: View {
    @Environment(EventKitService.self) private var eventKit
    @AppStorage(EventKitService.badgeEnabledKey) private var badgeEnabled = false
    @AppStorage(EventKitService.defaultCalendarKey) private var defaultCalendarID = ""
    @AppStorage(EventKitService.defaultListKey) private var defaultListID = ""

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

                Section("Integrations") {
                    integrationRow(name: "Google", detail: "Meet links and Drive attachments", comingSoon: true)
                    integrationRow(name: "Zoom", detail: "Create and join meetings", comingSoon: true)
                    integrationRow(name: "Notion", detail: "Two-way task sync", comingSoon: true)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("0.1 (MVP)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
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
