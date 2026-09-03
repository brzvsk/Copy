import SwiftUI

/// The single icon-only button used across Copy (shelf header, card hover
/// actions, etc.). It guarantees a generous, fully-hittable target (a plain `Button` with
/// a sized frame + `contentShape` — SwiftUI's `Menu`/borderless styles only made the glyph
/// pixels clickable), shows a hover highlight so the target is visible, and carries a
/// tooltip via `.help` (which also serves as the accessibility label).
struct IconButton: View {
    let systemName: String
    var fontSize: CGFloat = 12
    var size: CGSize = CGSize(width: 28, height: 26)
    var tint: Color = .secondary
    /// Tooltip shown on hover, and the accessibility label.
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size.width, height: size.height)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.09) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
