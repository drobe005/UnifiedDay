import SwiftUI

/// What the Mac menu bar commands act on. The window's RootView publishes it, so the
/// menus always reach the window in front.
struct AppCommandActions {
    var tabs: [AppTab]
    var canAdd: Bool
    var newItem: () -> Void
    var refresh: () -> Void
    var select: (AppTab) -> Void
}

extension FocusedValues {
    @Entry var appCommands: AppCommandActions?
}

extension EnvironmentValues {
    /// The same actions as the menus, for buttons inside the Mac screens.
    @Entry var appActions: AppCommandActions?
}

extension Scene {
    /// The Mac window's starting size and its menu bar commands. Nothing on iPhone.
    func udMacWindow() -> some Scene {
        #if os(macOS)
        defaultSize(width: 1280, height: 820)
            // No title bar: the sidebar runs to the top, like the Figma Mac page.
            .windowStyle(.hiddenTitleBar)
            .windowBackgroundDragBehavior(.enabled)
            .commands { UnifiedDayCommands() }
        #else
        self
        #endif
    }
}

extension View {
    /// Mac only: the window gets a minimum size, and Edit > Undo (Cmd Z) reverses
    /// the last change, where the iPhone uses a shake.
    func udMacWindowContent(
        undoTitle: String?,
        undoID: UUID?,
        undo: @escaping () -> Void
    ) -> some View {
        #if os(macOS)
        self
            .frame(minWidth: 1000, minHeight: 620)
            .modifier(MacUndo(title: undoTitle, id: undoID, undo: undo))
        #else
        self
        #endif
    }

    /// Mac only: gives a sheet a sensible size, since Mac sheets otherwise shrink
    /// to fit their content.
    func udSheetSize(minWidth: CGFloat = 480, minHeight: CGFloat = 560) -> some View {
        #if os(macOS)
        frame(minWidth: minWidth, idealWidth: minWidth + 60, minHeight: minHeight, idealHeight: minHeight + 80)
        #else
        self
        #endif
    }
}

#if os(macOS)
/// File, View and app menu commands.
private struct UnifiedDayCommands: Commands {
    @FocusedValue(\.appCommands) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Item") { actions?.newItem() }
                .keyboardShortcut("n")
                .disabled(actions?.canAdd != true)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") { actions?.select(.settings) }
                .keyboardShortcut(",")
                .disabled(actions == nil)
        }
        CommandGroup(before: .sidebar) {
            ForEach(Array((actions?.tabs ?? AppTab.movable).enumerated()), id: \.element) { index, tab in
                Button(tab.title) { actions?.select(tab) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                    .disabled(actions == nil)
            }
            Divider()
            Button("Refresh") { actions?.refresh() }
                .keyboardShortcut("r")
                .disabled(actions == nil)
            Divider()
        }
    }
}

/// Puts the last change on the window's undo menu. Only the latest change can be
/// undone, matching the shake on iPhone.
private struct MacUndo: ViewModifier {
    let title: String?
    let id: UUID?
    let undo: () -> Void

    @Environment(\.undoManager) private var undoManager
    @State private var target = UndoTarget()

    func body(content: Content) -> some View {
        content.onChange(of: id) {
            guard let undoManager else { return }
            undoManager.removeAllActions(withTarget: target)
            guard let title else { return }
            let action = undo
            undoManager.registerUndo(withTarget: target) { _ in
                MainActor.assumeIsolated { action() }
            }
            // The menu adds "Undo" in front, so "Undo Delete" becomes "Delete".
            undoManager.setActionName(title.replacingOccurrences(of: "Undo ", with: ""))
        }
    }
}

/// A stable owner for the registered undo, so it can be cleared when replaced.
private final class UndoTarget {}

#endif
