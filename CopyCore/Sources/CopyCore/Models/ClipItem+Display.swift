import Foundation

public extension ClipItem {
    /// One-line human title for menus and compact rows.
    var menuTitle: String {
        switch kind {
        case .image:
            return "Image"
        case .file:
            return plainText?.components(separatedBy: "\n").first ?? "File"
        default:
            let text = (plainText ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            return text.count > 50 ? String(text.prefix(50)) + "…" : text
        }
    }
}
