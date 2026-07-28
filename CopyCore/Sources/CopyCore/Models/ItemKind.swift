import Foundation

public enum ItemKind: String, Codable, Sendable {
    case text, richText, link, image, file, color

    /// `.link` only when the entire trimmed text is a single http(s) URL.
    public static func forText(_ text: String) -> ItemKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(where: { $0.isWhitespace }),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return .text }
        return .link
    }
}
