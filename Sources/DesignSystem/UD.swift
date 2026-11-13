import SwiftUI
#if os(iOS)
import UIKit
#endif

/// UnifiedDay design tokens. The colors live in Assets.xcassets/Colors, each with a
/// light and dark version, and match the "UnifiedDay" styles in the Figma file.
enum UD {
    // MARK: Brand (from the app icon)
    static let brand50 = Color("Brand50")
    static let brand100 = Color("Brand100")
    static let brand200 = Color("Brand200")
    static let brand500 = Color("Brand500")
    /// Buttons, active states, toggles.
    static let brand600 = Color("Brand600")
    /// Links and brand text.
    static let brand700 = Color("Brand700")

    // MARK: Accent (the icon's orange checkmark). Fills and graphics, not text.
    static let orange100 = Color("Orange100")
    static let orange500 = Color("Orange500")
    static let orange700 = Color("Orange700")

    // MARK: Text
    static let textPrimary = Color("TextPrimary")
    static let textStrong = Color("TextStrong")
    static let textSecondary = Color("TextSecondary")
    static let textTertiary = Color("TextTertiary")
    /// Placeholders, chevrons, disabled. Not for body text.
    static let textQuaternary = Color("TextQuaternary")

    // MARK: Borders
    static let borderPrimary = Color("BorderPrimary")
    static let borderSecondary = Color("BorderSecondary")

    // MARK: Backgrounds
    static let bgScreen = Color("BgScreen")
    static let bgCard = Color("BgCard")
    static let bgSubtle = Color("BgSubtle")
    static let bgSecondary = Color("BgSecondary")
    static let bgTertiary = Color("BgTertiary")
    static let bgQuaternary = Color("BgQuaternary")
    /// Behind form cards (note editor, folders, sheets), so white cards stand out.
    static let bgGrouped = Color("BgGrouped")

    // MARK: Status
    static let errorFg = Color("ErrorFg")
    static let errorBg = Color("ErrorBg")
    static let errorBorder = Color("ErrorBorder")
    static let successFg = Color("SuccessFg")
    static let successBg = Color("SuccessBg")
    static let successBorder = Color("SuccessBorder")
    static let warningFg = Color("WarningFg")
    static let warningBg = Color("WarningBg")
    static let warningBorder = Color("WarningBorder")

    // MARK: Shape and spacing
    static let cardRadius: CGFloat = 12
    static let screenPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 24

    /// Navigation bar and tab bar colors on iPhone. Called once at launch. The Mac
    /// keeps its standard window chrome.
    @MainActor
    static func configureAppearance() {
        #if os(iOS)
        let text = UIColor(named: "TextPrimary") ?? .label
        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        nav.largeTitleTextAttributes = [.foregroundColor: text]
        nav.titleTextAttributes = [.foregroundColor: text]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        let navEdge = UINavigationBarAppearance()
        navEdge.configureWithTransparentBackground()
        navEdge.largeTitleTextAttributes = [.foregroundColor: text]
        navEdge.titleTextAttributes = [.foregroundColor: text]
        UINavigationBar.appearance().scrollEdgeAppearance = navEdge

        UITabBar.appearance().unselectedItemTintColor = UIColor(named: "TextTertiary")
        #endif
    }
}
