import SwiftUI
import CopyCore

/// Edit-in-place sheet for a card's "Edit…" menu item and ⌘E: a rich text editor
/// (Bold/Italic/Underline/Strikethrough) with live character/word/line stats. Saving
/// writes an updated `public.rtf` representation alongside plain text — plain stays
/// canonical for "Paste as plain text" and search, rich is the alternate for a
/// formatted paste.
struct EditItemSheet: View {
    let item: ClipItem
    let store: ItemStore
    let onCancel: () -> Void
    let onSave: (NSAttributedString) -> Void

    @State private var attributedText: NSAttributedString
    @State private var original: NSAttributedString
    @StateObject private var editorController = RichTextEditorController()

    init(item: ClipItem, store: ItemStore, onCancel: @escaping () -> Void, onSave: @escaping (NSAttributedString) -> Void) {
        self.item = item
        self.store = store
        self.onCancel = onCancel
        self.onSave = onSave
        let seeded = Self.seedAttributedText(item: item, store: store)
        _attributedText = State(initialValue: seeded)
        _original = State(initialValue: seeded)
    }

    /// Seeds from the item's existing `public.rtf` representation when there is one
    /// (Copy captures RTF alongside plain text for rich-text copies), so re-editing a
    /// previously-formatted item doesn't flatten it back to plain text. Falls back to
    /// plain text for items that never had an RTF representation (or whose RTF fails to
    /// decode).
    private static func seedAttributedText(item: ClipItem, store: ItemStore) -> NSAttributedString {
        if let id = item.id,
           let reps = try? store.representations(forItemID: id),
           let rtfRep = reps.first(where: { $0.uti == "public.rtf" }),
           let decoded = NSAttributedString(rtf: rtfRep.data, documentAttributes: nil) {
            return decoded
        }
        return NSAttributedString(string: item.plainText ?? "")
    }

    private var isUnchanged: Bool {
        attributedText == original
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            formattingToolbar
            editor
            footer
        }
        .padding(16)
        .frame(width: 480, height: 360)
        // M7: outer sheet container only — the text view below keeps its own opaque
        // `.textBackgroundColor` fill for contrast, so glassing this container doesn't
        // touch legibility of the text being edited.
        .glassSurface(cornerRadius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Edit")
                .font(.headline)
            Spacer()
            Text(item.appName ?? "Unknown")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Quiet, borderless SF Symbol buttons — a clean B/I/U/S row rather than a loud
    /// ribbon toolbar. Bold/Italic/Underline get their conventional ⌘ shortcuts;
    /// Strikethrough has no system-standard one, so it's click-only.
    private var formattingToolbar: some View {
        HStack(spacing: 2) {
            FormatButton(symbol: "bold", label: "Bold", shortcut: "b", isActive: editorController.isBoldActive) {
                editorController.toggleBold()
            }
            FormatButton(symbol: "italic", label: "Italic", shortcut: "i", isActive: editorController.isItalicActive) {
                editorController.toggleItalic()
            }
            FormatButton(symbol: "underline", label: "Underline", shortcut: "u", isActive: editorController.isUnderlineActive) {
                editorController.toggleUnderline()
            }
            FormatButton(symbol: "strikethrough", label: "Strikethrough", isActive: editorController.isStrikethroughActive) {
                editorController.toggleStrikethrough()
            }
            Spacer()
        }
    }

    private var editor: some View {
        RichTextEditor(attributedText: $attributedText, controller: editorController)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }

    private var footer: some View {
        HStack(alignment: .center) {
            Text(statsText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Save") { onSave(attributedText) }
                .keyboardShortcut(.defaultAction)
                .disabled(isUnchanged)
        }
    }

    private var statsText: String {
        "\(editorController.characterCount) characters · \(editorController.wordCount) words · \(editorController.lineCount) lines"
    }
}

/// A single quiet toolbar button: SF Symbol only, no border — matches the shelf's
/// existing icon-button language (e.g. `DrawerMenu`'s ellipsis button) rather than
/// introducing a new, louder toolbar style. When `isActive` (the current selection/
/// typing attributes already carry this attribute), the icon tints to `accentColor`
/// over a soft accent-opacity fill — the same quiet selection language `SymbolSwatch`/
/// `EmojiSwatch` already use elsewhere, just at low opacity instead of a solid fill so
/// the row stays a clean B/I/U/S strip rather than a row of filled buttons.
private struct FormatButton: View {
    let symbol: String
    let label: String
    var shortcut: KeyEquivalent?
    var isActive: Bool = false
    let action: () -> Void

    init(symbol: String, label: String, shortcut: KeyEquivalent? = nil, isActive: Bool = false, action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.shortcut = shortcut
        self.isActive = isActive
        self.action = action
    }

    var body: some View {
        Group {
            if let shortcut {
                button.keyboardShortcut(shortcut, modifiers: .command)
            } else {
                button
            }
        }
    }

    private var button: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.15) : .clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
