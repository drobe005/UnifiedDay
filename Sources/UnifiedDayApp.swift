import SwiftUI

/// Working title: UnifiedDay. Rename the Xcode project when the app name is decided.
@main
struct UnifiedDayApp: App {
    @State private var eventKit = EventKitService()
    @State private var showingComposer = false
    @Environment(\.scenePhase) private var scenePhase

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
                if eventKit.accessGranted {
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
            .sheet(isPresented: $showingComposer) {
                ComposerView()
                    .environment(eventKit)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    eventKit.refreshOnForeground()
                }
            }
        }
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
