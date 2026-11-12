import SwiftUI

// Shared building blocks for the UnifiedDay redesign. Each one mirrors a piece of
// the Figma "Redesign (Untitled UI)" page so screens stay consistent.

// MARK: - Card

/// White rounded container with a hairline border and a soft shadow.
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
            .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
    }
}

/// Line between rows inside a card.
struct UDDivider: View {
    var body: some View {
        Rectangle().fill(UD.borderSecondary).frame(height: 1)
    }
}

// MARK: - Section

/// Small header label with an optional count badge.
struct UDSectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(UD.textStrong)
            if let count {
                UDBadge(text: "\(count)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Section header for plain SwiftUI lists of cards (Today, Calendar, Reminders).
struct UDListHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        UDSectionHeader(title: title, count: count)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}

/// Placeholder row for an empty section in a list of cards, drawn as a dashed box.
struct UDEmptyListRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(UD.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(UD.bgSubtle, in: RoundedRectangle(cornerRadius: UD.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: UD.cardRadius, style: .continuous)
                    .strokeBorder(UD.borderPrimary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}

/// Header, card and optional footer, like an inset grouped list section.
struct UDSection<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                UDSectionHeader(title: title)
            }
            UDCard { content }
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(UD.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Row

/// One line in a card: optional icon, title, optional subtitle, trailing content.
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
                    .font(.body.weight(.medium))
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
        .padding(.horizontal, 16)
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

/// Round checkbox for reminders. Done uses the orange check from the app icon.
struct ReminderCheck: View {
    let isCompleted: Bool
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 22

    var body: some View {
        ZStack {
            if isCompleted {
                Circle().fill(UD.orange500)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().strokeBorder(UD.borderPrimary, lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
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
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .background(
                    isEnabled ? UD.brand600 : UD.bgSecondary,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .opacity(configuration.isPressed ? 0.85 : 1)
                .shadow(color: .black.opacity(isEnabled ? 0.08 : 0), radius: 1, y: 1)
        }
    }
}

/// Small outlined button label with an icon, used as a menu label for filters.
struct FilterChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(UD.textTertiary)
            Text(text)
                .foregroundStyle(UD.textStrong)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(UD.textQuaternary)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(UD.bgCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(UD.borderPrimary)
        )
        .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
    }
}

/// Outlined neutral button.
struct UDSecondaryButtonStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(UD.textStrong)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                configuration.isPressed ? UD.bgSubtle : UD.bgCard,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(UD.borderPrimary)
            )
    }
}

/// Full-width outlined red button, for Delete at the bottom of a screen.
struct UDDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(UD.errorFg)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                configuration.isPressed ? UD.errorBg : UD.bgCard,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(UD.errorBorder)
            )
    }
}

/// Filled confirm button for a sheet's toolbar (Save, Done, Move).
/// The label is set to white because the toolbar picks a dark label in dark mode.
struct UDToolbarConfirmButton: View {
    var title = "Save"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ConfirmLabel(title: title)
        }
        .buttonStyle(.borderedProminent)
    }

    private struct ConfirmLabel: View {
        let title: String
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            Text(title)
                .foregroundStyle(isEnabled ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        }
    }
}

/// Tappable card row: soft highlight while pressed.
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

    /// Soft gray background for Apple's grouped forms, so the brand cards stand out.
    /// Pair with `udFormRow()` on each section.
    func udFormBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(UD.bgGrouped)
    }

    /// Card color for the rows of a grouped form section.
    func udFormRow() -> some View {
        listRowBackground(UD.bgCard)
    }
}

// MARK: - Form section labels

/// Section header for Apple's grouped forms, in the brand text color.
struct UDFormHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(UD.textStrong)
            .textCase(nil)
    }
}

/// Section footer for Apple's grouped forms.
struct UDFormFooter: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(UD.textTertiary)
    }
}
