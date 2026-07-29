import SwiftUI
import CopyCore

/// Sheet for a color card's "Adjust Color…" context menu item. Lets the user tweak a
/// copied color with a native `ColorPicker`, then re-copy it. Never mutates the stored
/// item — this is a re-copy with a tweak, matching Paste's "adjust copied colors" flow.
struct ColorAdjustSheet: View {
    let item: ClipItem
    let onCancel: () -> Void
    let onCopy: (String) -> Void

    @State private var color: Color

    init(item: ClipItem, onCancel: @escaping () -> Void, onCopy: @escaping (String) -> Void) {
        self.item = item
        self.onCancel = onCancel
        self.onCopy = onCopy
        _color = State(initialValue: Tokens.color(fromHex: item.plainText ?? ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Adjust Color")
                .font(.headline)
            ColorPicker("Color", selection: $color, supportsOpacity: false)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Copy") { onCopy(Tokens.hex(from: color)) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 260, height: 106)
    }
}
