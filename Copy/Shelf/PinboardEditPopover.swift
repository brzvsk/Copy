import SwiftUI
import CopyCore

/// Create/rename UI for a pinboard: name field + symbol picker + emoji picker + color
/// swatches, shared by the "+" button (create mode) and a tab's "Rename…" context menu
/// item (rename mode). Emoji and color are optional, user-chosen identity (like Finder
/// tags or Things areas) — never an auto-applied card decoration.
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

    /// Curated emoji categories for the full picker, modeled on the standard system
    /// character-viewer groupings. Not exhaustive (Unicode defines thousands of
    /// emoji) but broad enough that any commonly used emoji, including ZWJ sequences
    /// (family, professions, flags) and skin-tone variants, is reachable without
    /// leaving the popover. "No emoji" is a separate Clear affordance below, not a
    /// grid entry.
    private struct EmojiCategory {
        let name: String
        let symbol: String
        let emojis: [String]
    }

    private static let emojiCategories: [EmojiCategory] = [
        EmojiCategory(name: "Smileys & People", symbol: "face.smiling", emojis: [
            "😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂", "🙃",
            "😉", "😊", "😇", "🥰", "😍", "🤩", "😘", "😋", "😜", "🤪",
            "🤗", "🤔", "🤨", "😐", "🙄", "😏", "😴", "🤒", "🤕", "🥵",
            "🥶", "😵", "🤠", "🥳", "😎", "🤓", "😕", "🙁", "😮", "😲",
            "😢", "😭", "😱", "😡", "🤬", "😈", "💀", "👻", "🤖", "🎃",
            "👋", "🤝", "👍", "👍🏽", "👎", "👏", "🙌", "🙏", "💪", "👶",
            "🧑‍💻", "👨‍👩‍👧‍👦", "❤️", "💔",
        ]),
        EmojiCategory(name: "Animals & Nature", symbol: "pawprint", emojis: [
            "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯",
            "🦁", "🐮", "🐷", "🐸", "🐵", "🐔", "🐧", "🐦", "🐤", "🦆",
            "🦅", "🦉", "🦇", "🐺", "🐴", "🦄", "🐝", "🐛", "🦋", "🐌",
            "🐞", "🐢", "🐍", "🦎", "🐙", "🦑", "🦀", "🐠", "🐟", "🐬",
            "🐳", "🐋", "🦈", "🐘", "🦒", "🦓", "🐪", "🐐", "🐑", "🐄",
            "🌵", "🌲", "🌳", "🌴", "🌱", "🍀", "🌸", "🌻", "🌹", "🍁",
        ]),
        EmojiCategory(name: "Food & Drink", symbol: "fork.knife", emojis: [
            "🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐",
            "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🥑", "🥦", "🥕",
            "🌽", "🥔", "🍞", "🥐", "🧀", "🥚", "🍳", "🥞", "🥓", "🍔",
            "🍟", "🍕", "🌭", "🥪", "🌮", "🌯", "🍝", "🍜", "🍣", "🍱",
            "🍤", "🍙", "🍦", "🍩", "🍪", "🎂", "🍰", "🍫", "🍿", "🍯",
            "☕️", "🍵", "🍺", "🍷", "🍸", "🥂", "🧃", "🥛",
        ]),
        EmojiCategory(name: "Activity", symbol: "sportscourt", emojis: [
            "⚽️", "🏀", "🏈", "⚾️", "🥎", "🎾", "🏐", "🏉", "🎱", "🏓",
            "🏸", "🥊", "🥋", "⛳️", "🏹", "🎣", "🥌", "🎿", "⛷️", "🏂",
            "🏋️", "🤼", "🤸", "⛹️", "🤺", "🏇", "🧘", "🏄", "🏊", "🚴",
            "🚵", "🏆", "🥇", "🥈", "🥉", "🎖️", "🎗️", "🎫", "🎪", "🎭",
            "🎨", "🎬", "🎤", "🎧", "🎼", "🎹", "🥁", "🎷", "🎸", "🎻",
            "🎲", "♟️", "🎯", "🎳", "🎮", "🕹️",
        ]),
        EmojiCategory(name: "Travel & Places", symbol: "car", emojis: [
            "🚗", "🚕", "🚙", "🚌", "🏎️", "🚓", "🚑", "🚒", "🚚", "🚲",
            "🛵", "🏍️", "🚨", "🚂", "🚆", "🚇", "🚊", "✈️", "🛫", "🛬",
            "🛩️", "🚀", "🛸", "🚁", "⛵️", "🚤", "🛳️", "⛴️", "🚢", "⚓️",
            "🚧", "🚦", "🚥", "🗺️", "🗽", "🗼", "🏰", "🏯", "🎡", "🎢",
            "🎠", "⛲️", "🏖️", "🏝️", "🏜️", "🌋", "⛰️", "🏔️", "🗻", "🏕️",
            "🏠", "🏢", "🏬", "🏥", "🏦", "🏨", "⛪️", "🕌", "🕍", "🛕",
        ]),
        EmojiCategory(name: "Objects", symbol: "lightbulb", emojis: [
            "⌚️", "📱", "💻", "⌨️", "🖥️", "🖨️", "🖱️", "🕹️", "💽", "💾",
            "📷", "📸", "🎥", "📞", "☎️", "📺", "📻", "🎙️", "🧭", "⏰",
            "⏳", "🔋", "🔌", "💡", "🔦", "🕯️", "🧯", "💸", "💵", "💳",
            "💎", "🧰", "🔧", "🔨", "🛠️", "⚙️", "🔩", "⛓️", "🔫", "🧲",
            "🔭", "🔬", "💊", "🩹", "🩺", "🚪", "🪞", "🛏️", "🛋️", "🪑",
            "🚽", "🚿", "🛁", "🧴", "🧹", "🧺", "🧻", "🧼", "🧽", "🛒",
        ]),
        EmojiCategory(name: "Symbols", symbol: "number", emojis: [
            "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔",
            "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "☮️", "✝️",
            "☪️", "🕉️", "☸️", "✡️", "🔯", "☯️", "🔀", "🔁", "🔂", "▶️",
            "⏸️", "⏹️", "⏭️", "⏮️", "⏩", "⏪", "🔼", "🔽", "➡️", "⬅️",
            "⬆️", "⬇️", "↔️", "🔄", "➕", "➖", "➗", "✖️", "♾️", "‼️",
            "⁉️", "❓", "❗", "✅", "❌", "♻️", "©️", "®️", "™️", "🔟",
        ]),
        EmojiCategory(name: "Flags", symbol: "flag", emojis: [
            "🏁", "🚩", "🎌", "🏳️", "🏳️‍🌈", "🏴‍☠️", "🇺🇸", "🇬🇧", "🇨🇦", "🇦🇺",
            "🇩🇪", "🇫🇷", "🇮🇹", "🇪🇸", "🇵🇹", "🇧🇷", "🇲🇽", "🇯🇵", "🇰🇷", "🇨🇳",
            "🇮🇳", "🇷🇺", "🇳🇱", "🇸🇪", "🇳🇴", "🇩🇰", "🇫🇮", "🇨🇭", "🇮🇪", "🇵🇱",
        ]),
    ]

    /// Reduces arbitrary text to a single emoji grapheme cluster. Swift's `Character`
    /// already treats a full ZWJ sequence (family, professions), a flag (regional
    /// indicator pair), or a skin-tone-modified emoji as one element, so taking the
    /// first `Character` and re-wrapping it as a `String` guarantees the store never
    /// receives more than one visual emoji. Empty input becomes `nil` ("no emoji",
    /// falls back to the SF Symbol), matching M6's schema.
    private static func singleGrapheme(_ text: String) -> String? {
        text.first.map(String.init)
    }

    /// In-memory "recently used" convenience (session-only, not persisted); resets on
    /// relaunch, which is fine for a lightweight discovery aid.
    private static var recentEmojis: [String] = []

    private static func recordRecent(_ emoji: String?) {
        guard let emoji, !emoji.isEmpty else { return }
        recentEmojis.removeAll { $0 == emoji }
        recentEmojis.insert(emoji, at: 0)
        if recentEmojis.count > 12 {
            recentEmojis.removeLast(recentEmojis.count - 12)
        }
    }

    /// A curated, system-ish palette. Empty hex means "no color".
    static let colorOptions: [(name: String, hex: String)] = [
        ("None", ""),
        ("Red", "FF3B30"),
        ("Orange", "FF9500"),
        ("Yellow", "FFCC00"),
        ("Green", "34C759"),
        ("Blue", "007AFF"),
        ("Purple", "AF52DE"),
        ("Pink", "FF2D55"),
        ("Graphite", "8E8E93"),
    ]

    let mode: Mode
    let onCommit: (String, String, String?, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var symbol: String
    @State private var emoji: String?
    @State private var tint: String
    @State private var emojiCategoryIndex = 0
    @FocusState private var nameFocused: Bool

    init(mode: Mode, onCommit: @escaping (String, String, String?, String) -> Void) {
        self.mode = mode
        self.onCommit = onCommit
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _symbol = State(initialValue: "pin")
            _emoji = State(initialValue: nil)
            _tint = State(initialValue: "")
        case .rename(let pinboard):
            _name = State(initialValue: pinboard.name)
            _symbol = State(initialValue: pinboard.symbol)
            _emoji = State(initialValue: pinboard.emoji)
            _tint = State(initialValue: pinboard.tint)
        }
    }

    private var isCreate: Bool {
        if case .create = mode { return true }
        return false
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Tabs shown above the emoji grid: a "Recent" tab first when there's history
    /// from earlier in this app session, followed by the fixed category list.
    private var emojiCategoryTabs: [(name: String, symbol: String)] {
        var tabs: [(name: String, symbol: String)] = []
        if !Self.recentEmojis.isEmpty {
            tabs.append(("Recent", "clock"))
        }
        tabs.append(contentsOf: Self.emojiCategories.map { ($0.name, $0.symbol) })
        return tabs
    }

    private var currentCategoryEmojis: [String] {
        if !Self.recentEmojis.isEmpty {
            if emojiCategoryIndex == 0 { return Self.recentEmojis }
            return Self.categoryEmojis(at: emojiCategoryIndex - 1)
        }
        return Self.categoryEmojis(at: emojiCategoryIndex)
    }

    /// Bounds-checked access into `emojiCategories`; returns an empty grid rather
    /// than crashing if the index is ever momentarily out of range.
    private static func categoryEmojis(at index: Int) -> [String] {
        guard emojiCategories.indices.contains(index) else { return [] }
        return emojiCategories[index].emojis
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Pinboard Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(commit)

            VStack(alignment: .leading, spacing: 6) {
                Text("Symbol")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                    ForEach(Self.symbols, id: \.self) { candidate in
                        SymbolSwatch(symbol: candidate, isSelected: candidate == symbol) {
                            symbol = candidate
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Emoji")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let currentEmoji = emoji {
                        Text(currentEmoji)
                            .font(.system(size: 16))
                        Button("Clear") { emoji = nil }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Text("None")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(emojiCategoryTabs.indices, id: \.self) { index in
                            EmojiCategoryTab(
                                symbol: emojiCategoryTabs[index].symbol,
                                name: emojiCategoryTabs[index].name,
                                isSelected: index == emojiCategoryIndex
                            ) {
                                emojiCategoryIndex = index
                            }
                        }
                    }
                }

                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                        ForEach(currentCategoryEmojis, id: \.self) { candidate in
                            EmojiSwatch(emoji: candidate, isSelected: candidate == emoji) {
                                emoji = Self.singleGrapheme(candidate)
                            }
                        }
                    }
                }
                .frame(height: 168)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Color")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    ForEach(Self.colorOptions, id: \.hex) { option in
                        ColorSwatch(name: option.name, hex: option.hex, isSelected: option.hex == tint) {
                            tint = option.hex
                        }
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
        .frame(width: 280)
        .onAppear { nameFocused = true }
    }

    private func commit() {
        guard !trimmedName.isEmpty else { return }
        Self.recordRecent(emoji)
        onCommit(trimmedName, symbol, emoji, tint)
        dismiss()
    }
}

private struct SymbolSwatch: View {
    let symbol: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    /// Human-readable name for VoiceOver; most symbol identifiers already read fine as
    /// a single word, a couple need a friendlier label.
    private var accessibleName: String {
        switch symbol {
        case "chevron.left.forwardslash.chevron.right": return "Code"
        case "doc.text": return "Document"
        case "creditcard": return "Credit Card"
        default: return symbol.capitalized
        }
    }

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
        .accessibilityLabel(accessibleName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct EmojiSwatch: View {
    let emoji: String?
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    private var accessibleName: String {
        emoji ?? "No Emoji"
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let emoji {
                    Text(emoji).font(.system(size: 15))
                } else {
                    Image(systemName: "circle.slash")
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.6))
                }
            }
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : (isHovering ? Color.primary.opacity(0.08) : .clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibleName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A small category tab above the emoji grid (Recent + the standard groupings).
/// Icon-only with a tooltip, mirroring `SymbolSwatch`'s selection styling.
private struct EmojiCategoryTab: View {
    let symbol: String
    let name: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.7))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? Color.accentColor : (isHovering ? Color.primary.opacity(0.08) : .clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ColorSwatch: View {
    let name: String
    let hex: String
    let isSelected: Bool
    let action: () -> Void

    private var swatchColor: Color? {
        hex.isEmpty ? nil : Tokens.color(fromHex: hex)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(swatchColor ?? Color.clear)
                if swatchColor == nil {
                    Circle().stroke(Color.primary.opacity(0.35), lineWidth: 1)
                    Image(systemName: "slash.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 20, height: 20)
            .overlay(
                Circle()
                    .stroke(Color.primary, lineWidth: isSelected ? 2 : 0)
                    .padding(-2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
