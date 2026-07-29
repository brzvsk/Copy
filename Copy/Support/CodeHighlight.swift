import SwiftUI
import CopyCore

/// Token → color mapping for on-device syntax highlighting. This is CONTENT coloring
/// on the code glyphs themselves (like Xcode's editor), not chrome — it's intentionally
/// separate from any card/border styling. Colors are SwiftUI's named system colors,
/// which are dynamic (each has a light- and dark-appearance variant baked in), so they
/// read correctly in both without any extra branching here.
enum CodeHighlightPalette {
    static func color(for kind: TokenKind) -> Color {
        switch kind {
        case .keyword: return .purple
        case .string: return .red
        case .comment: return .secondary
        case .number: return .teal
        case .type: return .blue
        case .plain: return .primary
        }
    }
}

/// Builds a single concatenated `Text` from `text` with each `token`'s substring
/// colored per `CodeHighlightPalette`; everything outside a token range is left at the
/// default (primary) color. Font is intentionally left to the caller's `.font(...)`
/// modifier on the returned `Text` — every run here is otherwise plain, so one outer
/// `.font()` cascades to the whole concatenation, matching how the plain-text path
/// already applies `Tokens.bodyMono`/mono system font today.
func highlightedText(_ text: String, tokens: [HighlightToken]) -> Text {
    guard !tokens.isEmpty else { return Text(text) }
    let ns = text as NSString
    let length = ns.length
    var result = Text(verbatim: "")
    var cursor = 0
    for token in tokens.sorted(by: { $0.range.location < $1.range.location }) {
        // Defensive: `SyntaxHighlighter` guarantees sorted, non-overlapping,
        // in-bounds ranges, but this is a display path — a malformed token should
        // never crash the shelf, just be skipped.
        guard token.range.location >= cursor, token.range.location + token.range.length <= length else { continue }
        if token.range.location > cursor {
            result = result + Text(ns.substring(with: NSRange(location: cursor, length: token.range.location - cursor)))
        }
        result = result + Text(ns.substring(with: token.range))
            .foregroundColor(CodeHighlightPalette.color(for: token.kind))
        cursor = token.range.location + token.range.length
    }
    if cursor < length {
        result = result + Text(ns.substring(with: NSRange(location: cursor, length: length - cursor)))
    }
    return result
}

/// Caches `CodeDetector`/`SyntaxHighlighter` results so scrolling the shelf or
/// reopening the preview doesn't re-tokenize on every render. Entries are keyed by
/// `"<item uuid>#<cap>"` — the cap is part of the key because the card (short cap) and
/// the preview pane (longer cap) ask about the same item at different lengths, and
/// keying by uuid alone would have them evict each other on every switch. An entry is
/// recomputed whenever the capped text it was built from no longer matches (covers
/// `EditItemSheet` rewriting an item's `plainText` after the cache already has it).
@MainActor
final class CodeHighlightCache {
    static let shared = CodeHighlightCache()

    private struct Entry {
        let textHash: Int
        let language: CodeLanguage?
        let tokens: [HighlightToken]
    }

    private var entries: [String: Entry] = [:]
    /// Bounds memory for very long shelf histories. Eviction is a blunt "clear
    /// everything" rather than real LRU bookkeeping — simple, and at this scale
    /// (a few hundred small entries) the occasional full recompute is unnoticeable.
    private let capacity = 500

    func result(for text: String, uuid: String, cap: Int) -> (language: CodeLanguage?, tokens: [HighlightToken]) {
        let capped = String(text.prefix(cap))
        let hash = capped.hashValue
        let key = "\(uuid)#\(cap)"
        if let entry = entries[key], entry.textHash == hash {
            return (entry.language, entry.tokens)
        }
        let language = CodeDetector.detect(capped)
        let tokens = language.map { SyntaxHighlighter.tokens(for: capped, language: $0) } ?? []
        if entries.count >= capacity { entries.removeAll() }
        entries[key] = Entry(textHash: hash, language: language, tokens: tokens)
        return (language, tokens)
    }
}
