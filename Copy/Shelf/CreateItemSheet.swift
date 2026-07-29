import SwiftUI
import CopyCore

/// New-item sheet for ⌘N and the status menu's "New Item…" action. Mirrors
/// `EditItemSheet`'s window/sheet structure. Creates a user-authored text item via
/// `ItemStore.createTextItem` on save.
struct CreateItemSheet: View {
    let onCancel: () -> Void
    let onCreate: (String, String?) -> Void

    @State private var title = ""
    @State private var text = ""

    private var isTextEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            TextField("Title (optional)", text: $title)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $text)
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
            footer
        }
        .padding(16)
        .frame(width: 480, height: 320)
        // M7: outer sheet container only — the text editor below keeps its own opaque
        // `.textBackgroundColor` fill for contrast, so glassing this container doesn't
        // touch legibility of the text being composed. Mirrors `EditItemSheet`.
        .glassSurface(cornerRadius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var header: some View {
        Text("New Item")
            .font(.headline)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Create") {
                onCreate(text, title.isEmpty ? nil : title)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isTextEmpty)
        }
    }
}

/// Rename sheet for a card's "Rename…" context menu item, seeded from the item's
/// current custom title. Saving an empty title clears the custom title, reverting
/// display to the auto-generated one.
struct RenameItemSheet: View {
    let item: ClipItem
    let onCancel: () -> Void
    let onRename: (String) -> Void

    @State private var title: String

    init(item: ClipItem, onCancel: @escaping () -> Void, onRename: @escaping (String) -> Void) {
        self.item = item
        self.onCancel = onCancel
        self.onRename = onRename
        _title = State(initialValue: item.title ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rename")
                .font(.headline)
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onRename(title) }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { onRename(title) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320, height: 108)
    }
}
