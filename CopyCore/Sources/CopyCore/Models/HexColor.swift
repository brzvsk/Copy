import Foundation

/// Recognizes when a copied text item is, by itself, a hex color so the shelf can show
/// the actual color as a swatch instead of the raw string.
public enum HexColor {
    /// The canonical `#RRGGBB` form if `text` is a standalone hex color (3 or 6 hex
    /// digits, an optional leading `#`, surrounding whitespace allowed); otherwise nil.
    /// Shorthand like `#abc` expands to `#AABBCC`.
    public static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6 else { return nil }
        return "#" + hex.uppercased()
    }
}
