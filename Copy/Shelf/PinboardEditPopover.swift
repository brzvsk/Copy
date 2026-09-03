import SwiftUI
import CopyCore

/// Create/rename UI for a pinboard: name field + emoji picker, shared by the "+"
/// button (create mode) and a tab's "Edit…" context menu item. Emoji is the only
/// optional visual identity shown on pinboard tabs.
struct PinboardEditPopover: View {
    enum Mode {
        case create
        case rename(Pinboard)
    }

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
            "📌", "🔑", "📁", "📚", "🖼️", "💼", "🏷️", "📝",
        ]),
        EmojiCategory(name: "Symbols", symbol: "number", emojis: [
            "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔",
            "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "☮️", "✝️",
            "☪️", "🕉️", "☸️", "✡️", "🔯", "☯️", "🔀", "🔁", "🔂", "▶️",
            "⏸️", "⏹️", "⏭️", "⏮️", "⏩", "⏪", "🔼", "🔽", "➡️", "⬅️",
            "⬆️", "⬇️", "↔️", "🔄", "➕", "➖", "➗", "✖️", "♾️", "‼️",
            "⁉️", "❓", "❗", "✅", "❌", "♻️", "©️", "®️", "™️", "🔟",
            "⭐️", "🔗", "🌐",
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

    let mode: Mode
    let onCommit: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var emoji: String?
    @State private var emojiCategoryIndex = 0
    @FocusState private var nameFocused: Bool

    init(mode: Mode, onCommit: @escaping (String, String?) -> Void) {
        self.mode = mode
        self.onCommit = onCommit
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _emoji = State(initialValue: nil)
        case .rename(let pinboard):
            _name = State(initialValue: pinboard.name)
            _emoji = State(initialValue: pinboard.emoji)
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
                HStack {
                    Text("Emoji")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let currentEmoji = emoji {
                        // Deliberately one point larger than the grid swatches (15):
                        // this is the "show the current selection prominently" readout,
                        // so a slight emphasis over the grid is intentional, not drift.
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

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isCreate ? "Create" : "Save", action: commit)
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
        onCommit(trimmedName, emoji)
        dismiss()
    }
}

private struct EmojiSwatch: View {
    let emoji: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: 15))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor : (isHovering ? Color.primary.opacity(0.08) : .clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(emoji)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A small category tab above the emoji grid (Recent + the standard groupings).
/// Icon-only with a tooltip, using the same quiet selection styling as emoji swatches.
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
