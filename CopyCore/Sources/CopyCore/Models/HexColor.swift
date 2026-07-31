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

    /// Whether `text` should be *classified* as a color item (kind `.color`), not merely
    /// displayed as a swatch. It must be a standalone hex; bare hex (no `#`) additionally
    /// must contain a hex letter (a-f), so a plain digit string like "123456" — which is
    /// valid hex but almost never a color — stays text.
    public static func isColorText(_ text: String) -> Bool {
        guard normalized(text) != nil else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("#") || trimmed.contains(where: { $0.isLetter })
    }
}
