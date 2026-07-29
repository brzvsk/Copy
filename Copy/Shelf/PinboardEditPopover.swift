import SwiftUI
import CopyCore

/// Create/rename UI for a pinboard: name field + symbol picker, shared by the
/// "+" button (create mode) and a tab's "Rename…" context menu item (rename mode).
struct PinboardEditPopover: View {
    enum Mode {
        case create
        case rename(Pinboard)
    }

    static let symbols = [
        "pin", "star", "folder", "briefcase", "chevron.left.forwardslash.chevron.right",
        "doc.text", "photo", "link", "envelope", "cart", "creditcard", "key",
        "terminal", "paintbrush", "book", "bookmark", "tag", "tray",
        "archivebox", "calendar", "person", "globe", "lightbulb", "heart",
    ]

    let mode: Mode
    let onCommit: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var symbol: String
    @FocusState private var nameFocused: Bool

    init(mode: Mode, onCommit: @escaping (String, String) -> Void) {
        self.mode = mode
        self.onCommit = onCommit
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _symbol = State(initialValue: "pin")
        case .rename(let pinboard):
            _name = State(initialValue: pinboard.name)
            _symbol = State(initialValue: pinboard.symbol)
        }
    }

    private var isCreate: Bool {
        if case .create = mode { return true }
        return false
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Pinboard Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(commit)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(Self.symbols, id: \.self) { candidate in
                    SymbolSwatch(symbol: candidate, isSelected: candidate == symbol) {
                        symbol = candidate
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isCreate ? "Create" : "Rename", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 260)
        .onAppear { nameFocused = true }
    }

    private func commit() {
        guard !trimmedName.isEmpty else { return }
        onCommit(trimmedName, symbol)
        dismiss()
    }
}

private struct SymbolSwatch: View {
    let symbol: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.8))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor : (isHovering ? Color.primary.opacity(0.08) : .clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
