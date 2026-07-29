import SwiftUI
import CopyCore

/// Edit-in-place sheet for a card's "Edit…" menu item and ⌘E. Rich text and links are
/// edited and saved as plain text — `ItemStore.replaceContent` always writes plain text,
/// so this is the one place that behavior needs explaining to the user.
struct EditItemSheet: View {
    let item: ClipItem
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var text: String

    init(item: ClipItem, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.item = item
        self.onCancel = onCancel
        self.onSave = onSave
        _text = State(initialValue: item.plainText ?? "")
    }

    private var isUnchanged: Bool {
        text == (item.plainText ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            textEditor
            footer
        }
        .padding(16)
        .frame(width: 480, height: 320)
    }

    /// `.writingToolsBehavior(.complete)` requires macOS 15.0+ (verified against the
    /// macOS 26 SDK's SwiftUI.swiftinterface); on plain `TextEditor` the default
    /// `.automatic` behavior already offers Writing Tools on 15.0+, but `.complete`
    /// makes sure the full proofread/rewrite panel is offered rather than a limited
    /// inline-only variant. Gated so macOS 14 keeps the exact prior `TextEditor`.
    @ViewBuilder
    private var textEditor: some View {
        Group {
            if #available(macOS 15.0, *) {
                TextEditor(text: $text)
                    .writingToolsBehavior(.complete)
            } else {
                TextEditor(text: $text)
            }
        }
        .font(.system(size: 13, design: .monospaced))
        .scrollContentBackground(.hidden)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
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

    private var footer: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if item.kind == .richText {
                Text("Saving keeps plain text only")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(text) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isUnchanged)
            }
        }
    }
}
