import SwiftUI

enum Tokens {
    static let cardWidth: CGFloat = 184
    static let cardHeight: CGFloat = 244
    static let cardGap: CGFloat = 12
    static let cardRadius: CGFloat = 10
    static let shelfPadding: CGFloat = 20

    static let bodyMono = Font.system(size: 11, design: .monospaced)
    static let caption = Font.system(size: 10, weight: .medium)
    static let cardTitle = Font.system(size: 11, weight: .semibold)

    static func color(fromHex hex: String) -> Color {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard Scanner(string: cleaned).scanHexInt64(&value), cleaned.count == 6 else {
            return .gray
        }
        return Color(red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }

    static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
