import SwiftUI

/// A small keyboard-key chip (e.g. ⏎, Space, ⇧⌘V), shared by the shelf's first-run
/// empty-state hints and the dismissible keyboard legend along the shelf footer.
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 0.5)
                    )
            )
            .accessibilityLabel(text)
    }
}

/// A key chip followed by a short label, for legends and first-run hints.
struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            KeyCap(text: key)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(key): \(label)")
    }
}
