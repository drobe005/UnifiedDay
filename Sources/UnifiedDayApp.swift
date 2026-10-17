import SwiftUI

/// Working title: UnifiedDay. Rename the Xcode project when the app name is decided.
@main
struct UnifiedDayApp: App {
    @State private var eventKit = EventKitService()
    @State private var showingComposer = false

    var body: some Scene {
        WindowGroup {
            TabView {
                TodayView()
                    .tabItem { Label("Today", systemImage: "calendar.day.timeline.left") }
                RemindersListView()
                    .tabItem { Label("Reminders", systemImage: "checklist") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gear") }
            }
            .environment(eventKit)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showingComposer = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .padding(18)
                        .background(.tint, in: Circle())
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
                .padding()
                .accessibilityLabel("Add event or reminder")
            }
            .sheet(isPresented: $showingComposer) {
                ComposerView()
                    .environment(eventKit)
            }
            .task {
                eventKit.refreshAccessStatus()
            }
        }
    }
}
