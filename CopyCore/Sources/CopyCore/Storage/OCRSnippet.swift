import Foundation

/// Builds a short, single-line preview of an image item's recognized (OCR) text,
/// centered on where a search query matched, so a search result can show *why* an image
/// matched. The caller highlights the query within the returned snippet.
public enum OCRSnippet {
    /// A window of `recognizedText` around the first case- and diacritic-insensitive
    /// occurrence of `query`, collapsed to a single line, with a leading/trailing
    /// ellipsis where the text was trimmed. Returns nil when the query does not appear.
    public static func make(recognizedText: String, query: String, context: Int = 48) -> String? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }

        // OCR text is often multi-line; collapse runs of whitespace/newlines to single
        // spaces so the snippet reads as one clean line.
        let flat = recognizedText
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        guard let match = flat.range(of: trimmedQuery,
                                     options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }

        let lower = flat.index(match.lowerBound, offsetBy: -context, limitedBy: flat.startIndex)
            ?? flat.startIndex
        let upper = flat.index(match.upperBound, offsetBy: context, limitedBy: flat.endIndex)
            ?? flat.endIndex

        var snippet = String(flat[lower..<upper])
        if lower > flat.startIndex { snippet = "…" + snippet }
        if upper < flat.endIndex { snippet += "…" }
        return snippet
    }
}
