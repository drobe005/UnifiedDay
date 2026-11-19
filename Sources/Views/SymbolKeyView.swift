import SwiftUI

/// A key to the marks on schedule rows. Shown once in onboarding and kept in
/// Settings under Help. Each sample uses the same view the timeline draws.
struct SymbolKeyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            group("Rows") {
                entry("Event", "The bar takes the color of its calendar.") {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(UD.brand600)
                        .frame(width: 3, height: 22)
                        .frame(width: ReminderCheck.columnWidth, alignment: .leading)
                }
                UDDivider()
                entry("Task", "Tap the circle to mark it done.") {
                    ReminderCheck(isCompleted: false)
                }
                UDDivider()
                entry("Done", "A filled circle and a crossed-out title.") {
                    ReminderCheck(isCompleted: true)
                }
            }

            group("Details") {
                entry("Overdue", "A red time means the task is past due.") {
                    Text("9:00")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(UD.errorFg)
                }
                UDDivider()
                entry("Repeats", "The event or task happens again on a schedule.") {
                    Image(systemName: "repeat")
                        .foregroundStyle(UD.textTertiary)
                }
                UDDivider()
                entry("Has a note", "A UnifiedDay note is attached. Open the item to read it.") {
                    Image(systemName: "note.text")
                        .foregroundStyle(UD.textTertiary)
                }
                UDDivider()
                entry("List color", "The dot next to a heading in Tasks shows that list's color.") {
                    Circle()
                        .fill(UD.orange500)
                        .frame(width: 8, height: 8)
                }
            }

            group("Swipes") {
                entry("Swipe right", "Move it to tomorrow, next week, or a date you pick.") {
                    Image(systemName: "arrow.right")
                        .foregroundStyle(UD.brand600)
                }
                UDDivider()
                entry("Swipe left", "Delete it. You'll be asked first, and you can undo.") {
                    Image(systemName: "arrow.left")
                        .foregroundStyle(UD.errorFg)
                }
            }
        }
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(UD.textTertiary)
                .padding(.bottom, 4)
            content()
        }
    }

    /// One mark at the left, a name, and one sentence on what it means.
    private func entry(_ name: String, _ meaning: String, @ViewBuilder mark: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            mark()
                .frame(width: 44, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(UD.textPrimary)
                Text(meaning)
                    .font(.subheadline)
                    .foregroundStyle(UD.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// The key, shown once right after onboarding grants access.
struct SymbolKeyIntroView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("How to read your day")
                        .font(.largeTitle.bold())
                        .foregroundStyle(UD.textPrimary)
                    Text("Events and tasks share one timeline. These marks tell them apart.")
                        .font(.body)
                        .foregroundStyle(UD.textSecondary)
                    SymbolKeyView()
                    Text("You can find this again in Settings, under Help.")
                        .font(.footnote)
                        .foregroundStyle(UD.textTertiary)
                }
                .padding(.bottom, 16)
            }
            Button("Get Started") { dismiss() }
                .buttonStyle(UDPrimaryButtonStyle(fullWidth: true))
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .background(UD.bgScreen)
    }
}
