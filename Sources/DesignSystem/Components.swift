import SwiftUI

// Shared building blocks for UnifiedDay. They follow the minimal direction on the
// Figma "Primary Screens" page: plain rows with hairlines, small gray labels, and
// brand blue only for actions.

// MARK: - Card

/// White rounded container from the earlier card design. Only the screens that
/// have not moved to plain rows yet still use it.
struct UDCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(UD.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: UD.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: UD.cardRadius, style: .continuous)
                    .strokeBorder(UD.borderSecondary)
            )
    }
}

/// Hairline between rows.
struct UDDivider: View {
    var body: some View {
        Rectangle().fill(UD.divider).frame(height: 1)
    }
}

// MARK: - Section

/// Small gray label above a group of rows, like "Pinned" or "Due today · 1".
struct UDSectionHeader: View {
    let title: String
    var count: Int?
    /// A list or calendar color, shown as a small dot before the label.
    var dotColor: Color?

    private var label: String {
        count.map { "\(title) · \($0)" } ?? title
    }

    var body: some View {
        HStack(spacing: 6) {
            if let dotColor {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(UD.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Section header for plain SwiftUI lists (Today, Calendar, Reminders, Notes).
struct UDListHeader: View {
    let title: String
    var count: Int?
    var dotColor: Color?

    var body: some View {
        UDSectionHeader(title: title, count: count, dotColor: dotColor)
            .udListHeaderLayout()
    }
}

/// A list section heading that folds its rows open or shut when tapped.
/// The chevron points right when shut and down when open.
struct UDFoldableHeader: View {
    let title: String
    var count: Int?
    var dotColor: Color?
    let isCollapsed: Bool
    var isDisabled = false
    var showHint = "Shows this section"
    var hideHint = "Hides this section"
    let toggle: () -> Void

    var body: some View {
        Button {
            withAnimation { toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(UD.textTertiary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 14)
                UDSectionHeader(title: title, count: count, dotColor: dotColor)
            }
            .udListHeaderLayout()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(title)
        .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
        .accessibilityHint(isCollapsed ? showHint : hideHint)
    }
}

private extension View {
    /// Spacing and margins shared by every list section heading.
    func udListHeaderLayout() -> some View {
        textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .listRowInsets(UD.rowInsets)
    }
}

/// Placeholder line for an empty section in a plain list.
struct UDEmptyListRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(UD.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .udPlainRow()
    }
}

/// Small gray label, plain rows with hairlines between them, and an optional footer.
struct UDSection<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                UDSectionHeader(title: title)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
            }
            content
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(UD.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
    }
}

// MARK: - Row

/// One plain line: optional icon, title, optional subtitle, trailing content.
struct UDRow<Trailing: View>: View {
    var icon: String?
    var title: String
    var subtitle: String?
    var titleColor: Color = UD.textPrimary
    var showsChevron = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(UD.textTertiary)
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(titleColor)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(UD.textTertiary)
                }
            }
            Spacer(minLength: 8)
            trailing
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(UD.textQuaternary)
            }
        }
        .padding(.vertical, 12)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

extension UDRow where Trailing == EmptyView {
    init(icon: String? = nil, title: String, subtitle: String? = nil,
         titleColor: Color = UD.textPrimary, showsChevron: Bool = false) {
        self.init(icon: icon, title: title, subtitle: subtitle, titleColor: titleColor,
                  showsChevron: showsChevron) { EmptyView() }
    }
}

/// Trailing value text for a row, like "Apple default".
struct UDValue: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(UD.textTertiary)
            .lineLimit(1)
    }
}

// MARK: - Badge

enum UDTone {
    case gray, brand, success, warning, error

    var foreground: Color {
        switch self {
        case .gray: UD.textStrong
        case .brand: UD.brand700
        case .success: UD.successFg
        case .warning: UD.warningFg
        case .error: UD.errorFg
        }
    }

    var background: Color {
        switch self {
        case .gray: UD.bgSubtle
        case .brand: UD.brand50
        case .success: UD.successBg
        case .warning: UD.warningBg
        case .error: UD.errorBg
        }
    }

    var border: Color {
        switch self {
        case .gray: UD.borderSecondary
        case .brand: UD.brand200
        case .success: UD.successBorder
        case .warning: UD.warningBorder
        case .error: UD.errorBorder
        }
    }
}

/// Small pill label, optionally with a leading dot.
struct UDBadge: View {
    let text: String
    var tone: UDTone = .gray
    var dot = false

    var body: some View {
        HStack(spacing: 4) {
            if dot {
                Circle().fill(tone.foreground).frame(width: 6, height: 6)
            }
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(tone.background, in: Capsule())
        .overlay(Capsule().strokeBorder(tone.border))
    }
}

// MARK: - Featured icon

/// Icon on a soft colored circle, used in empty states and onboarding.
struct UDFeaturedIcon: View {
    let systemName: String
    var size: CGFloat = 48
    var accent = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(accent ? UD.orange700 : UD.brand600)
            .frame(width: size, height: size)
            .background(accent ? UD.orange100 : UD.brand100, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Reminder check

/// Round checkbox for reminders: a thin gray ring, filled brand blue when done.
/// Draws 26 points wide so it lines up with the event color bar, and takes taps
/// on a 44 point square around it.
struct ReminderCheck: View {
    let isCompleted: Bool
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 20

    /// Width of the marker column at the start of a schedule row.
    static let columnWidth: CGFloat = 26

    var body: some View {
        ZStack {
            if isCompleted {
                Circle().fill(UD.brand600)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().strokeBorder(UD.textQuaternary, lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
        // As tall as one line of body text, so the circle centers on the title.
        .frame(width: Self.columnWidth, height: 22, alignment: .leading)
        .contentShape(Rectangle().inset(by: -10))
    }
}

// MARK: - Buttons

/// Filled brand button.
struct UDPrimaryButtonStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        PrimaryLabel(configuration: configuration, fullWidth: fullWidth)
    }

    private struct PrimaryLabel: View {
        let configuration: Configuration
        let fullWidth: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(isEnabled ? Color.white : UD.textQuaternary)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .background(
                    isEnabled ? UD.brand600 : UD.bgSecondary,
                    in: RoundedRectangle(cornerRadius: UD.cardRadius, style: .continuous)
                )
                .opacity(configuration.isPressed ? 0.85 : 1)
        }
    }
}

/// Plain gray menu label with a small chevron, used for filters.
struct FilterChip: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(UD.textTertiary)
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }
}

/// Plain red text line, for Delete at the bottom of a screen.
struct UDDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(UD.errorFg)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Confirm button for a sheet's toolbar (Save, Done, Move), as bold brand text.
struct UDToolbarConfirmButton: View {
    var title = "Save"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).fontWeight(.semibold)
        }
        .tint(UD.brand600)
    }
}

/// Tappable row: soft highlight while pressed.
struct UDRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? UD.bgSubtle : Color.clear)
    }
}

// MARK: - Empty state

/// Centered icon, title, message and optional action.
struct UDEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            UDFeaturedIcon(systemName: icon, size: 56)
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(UD.textPrimary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(UD.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(UDPrimaryButtonStyle())
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Screen background

extension View {
    /// Brand screen background for lists, forms and scroll views.
    func udScreenBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(UD.bgScreen)
    }

    /// Turns one of Apple's forms into plain rows on the screen background, with
    /// hairlines between rows. Pair with `udFormRow()` on each section.
    func udFormBackground() -> some View {
        listStyle(.plain)
            .listSectionSpacing(0)
            .listRowSeparatorTint(UD.divider)
            .listSectionSeparator(.hidden)
            .environment(\.defaultMinListRowHeight, 52)
            .scrollContentBackground(.hidden)
            .background(UD.bgScreen)
    }

    /// Plain look for the rows of a form section: no card behind them, the screen
    /// margin on both sides, and hairlines that stop at the margin.
    func udFormRow() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(UD.rowInsets)
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
    }

    /// A row that draws its own hairline (or none): no background, no list
    /// separator, the screen margin on both sides.
    func udPlainRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(UD.rowInsets)
    }
}

// MARK: - Form section labels

/// Small gray section label for forms.
struct UDFormHeader: View {
    let title: String

    var body: some View {
        UDListHeader(title: title)
    }
}

/// Small gray note under a form section.
struct UDFormFooter: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(UD.textTertiary)
    }
}

// MARK: - Text tabs

/// A row of text tabs with a line under the chosen one, like Week and Month.
struct UDTextTabs<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 20) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? UD.textPrimary : UD.textTertiary)
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(isSelected ? UD.textPrimary : Color.clear)
                                .frame(height: 2)
                        }
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Navigation

/// Small gray line above a screen's large title, like the date above "Today".
/// It sits in the navigation bar's leading spot with no button background.
struct UDOverlineToolbarItem: ToolbarContent {
    let text: String

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) { label }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { label }
        }
    }

    private var label: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(UD.textTertiary)
            .lineLimit(1)
            .fixedSize()
            // Short text would otherwise center in the button-sized slot and sit off the margin.
            .frame(minWidth: 44, alignment: .leading)
            .accessibilityAddTraits(.isStaticText)
    }
}

extension View {
    /// Shows search as a magnifying glass button until it is tapped, where iOS supports it.
    @ViewBuilder
    func udMinimizedSearch() -> some View {
        if #available(iOS 26.0, *) {
            searchToolbarBehavior(.minimize)
        } else {
            self
        }
    }
}
