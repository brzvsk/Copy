import KeyboardShortcuts
import SwiftUI

/// The keyboard-and-tips cheat sheet reached from the shelf's drawer menu. A quiet
/// reference so the full move-set is always one click away without cluttering the shelf.
/// Hotkeys that the user can rebind are read live from their actual bindings.
struct TipsSheet: View {
    let onDone: () -> Void

    private var openHotkey: String {
        KeyboardShortcuts.getShortcut(for: .toggleShelf)?.description ?? "⇧⌘V"
    }

    private var pasteStackHotkey: String {
        KeyboardShortcuts.getShortcut(for: .togglePasteStack)?.description ?? "⇧⌘C"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyboard & Tips").font(.headline)
                Spacer()
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Open & paste", [
                        (openHotkey, "Open or hide Copy"),
                        ("↩", "Paste the selected card"),
                        ("⌥↩", "Paste as plain text"),
                        ("Space", "Preview the selected card"),
                        ("⌘O", "Open a link or file"),
                    ])
                    section("Navigate", [
                        ("← →", "Move between cards"),
                        ("⌘1–9", "Jump to a pinboard"),
                        ("Type", "Search your history"),
                    ])
                    section("Organize", [
                        ("Click title", "Rename a card"),
                        ("⌘⌫", "Delete the selected card"),
                        ("⌘Z", "Undo a delete"),
                        ("Drag", "Drop a card on a pinboard tab to keep it"),
                    ])
                    section("Paste stack", [
                        (pasteStackHotkey, "Toggle the paste stack"),
                        ("⌘V", "Paste the next queued item, again and again"),
                    ])
                }
                .padding(16)
            }
        }
        .frame(width: 420, height: 500)
    }

    private func section(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 11) {
                    KeyCap(text: row.0)
                    Text(row.1).font(.system(size: 13))
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
