import Foundation

/// Source languages `SyntaxHighlighter` knows how to tokenize. `.unknown` is reserved
/// for a future "this is code, but we can't tell which language" bucket; `detect(_:)`
/// never returns it today — it returns `nil` instead whenever confidence is low, since
/// callers only highlight when `detect(_:)` names a specific language.
public enum CodeLanguage: Equatable, Sendable {
    case swift
    case javascript
    case python
    case json
    case html
    case css
    case shell
    case unknown
}

/// Heuristic, dependency-free source-code detector. Deliberately conservative: it is
/// tuned to favor false negatives over false positives, because a prose paragraph
/// rendered in "code colors" reads as a much more obvious bug than a real code snippet
/// that stays uncolored. Every heuristic below requires more than one independent
/// signal (e.g. a structural shape *and* a minimum count of language-specific keyword
/// hits) before committing to a language, specifically so that a single coincidental
/// keyword in ordinary text ("this drug class...") can't flip the result.
public enum CodeDetector {
    /// Returns the best-guess language for `text`, or `nil` if `text` doesn't look
    /// confidently like code. Callers should pass whatever bounded slice of the item
    /// they intend to highlight (the app caps to a display prefix already); detection
    /// itself additionally caps its own scan of that input so a single call stays fast
    /// regardless of how much text is handed in.
    public static func detect(_ text: String) -> CodeLanguage? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        if let language = detectShebang(text) {
            return language
        }
        if isLikelyJSON(text) {
            return .json
        }

        let sample = String(text.prefix(sampleCap))
        if let language = detectScriptLanguage(sample) {
            return language
        }
        if isLikelyHTML(sample) {
            return .html
        }
        if isLikelyCSS(sample) {
            return .css
        }
        if isLikelyShellCommands(sample) {
            return .shell
        }
        return nil
    }

    /// Bound on how much of `text` the structural/keyword heuristics scan. Detection
    /// only needs a representative sample, not the whole paste, so this keeps `detect`
    /// O(1) with respect to arbitrarily large clipboard content.
    private static let sampleCap = 20_000

    // MARK: - Shebang

    /// `#!/usr/bin/env python3`, `#!/bin/bash`, etc. The single most reliable signal
    /// available, since a shebang line essentially never appears in prose.
    private static func detectShebang(_ text: String) -> CodeLanguage? {
        guard let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first,
              firstLine.hasPrefix("#!")
        else { return nil }
        let line = firstLine.lowercased()
        if line.contains("python") { return .python }
        if line.contains("node") { return .javascript }
        return .shell
    }

    // MARK: - JSON

    /// JSON gets a strict-parse fast path: if the trimmed text is bracket/brace
    /// delimited and small enough, a real `JSONSerialization` parse is both the
    /// cheapest and the most precise possible check (zero false positives, since
    /// prose never parses as JSON). Only very large pastes fall back to a structural
    /// approximation on a capped prefix.
    private static func isLikelyJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
                || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
        else { return false }

        if trimmed.utf8.count <= 100_000 {
            guard let data = trimmed.data(using: .utf8) else { return false }
            return (try? JSONSerialization.jsonObject(with: data)) != nil
        }

        let sample = String(trimmed.prefix(sampleCap))
        let hasQuotedKey = sample.range(of: #""[^"\\]*"\s*:"#, options: .regularExpression) != nil
        let openBraces = sample.filter { $0 == "{" }.count
        let closeBraces = sample.filter { $0 == "}" }.count
        return hasQuotedKey && openBraces > 0 && abs(openBraces - closeBraces) <= 1
    }

    // MARK: - Swift / JavaScript / Python

    /// Swift/JS require balanced braces plus at least two distinct strong signals
    /// (keywords, arrows, etc.) from that language's own list; Python's indentation
    /// block shape is checked first since it's a strong, brace-free signal on its own.
    private static func detectScriptLanguage(_ text: String) -> CodeLanguage? {
        let lines = text.components(separatedBy: .newlines)
        if hasPythonBlockShape(lines), countMatches(text, patterns: pythonSignals) >= 2 {
            return .python
        }

        let openBraces = text.filter { $0 == "{" }.count
        let closeBraces = text.filter { $0 == "}" }.count
        guard openBraces > 0, openBraces == closeBraces else { return nil }

        let swiftHits = countMatches(text, patterns: swiftSignals)
        let jsHits = countMatches(text, patterns: javascriptSignals)
        if swiftHits >= 2, swiftHits >= jsHits {
            return .swift
        }
        if jsHits >= 2 {
            return .javascript
        }
        return nil
    }

    /// True when some line looks like a Python block header (`def foo():`, `if x:`,
    /// ...) whose next non-blank line is indented further than it is. Ordinary prose
    /// essentially never has this shape, so it's treated as a strong signal even
    /// before checking keyword density.
    private static func hasPythonBlockShape(_ lines: [String]) -> Bool {
        guard let headerRegex = try? NSRegularExpression(pattern: #"^(def|class|if|elif|else|for|while|try|except|finally|with)\b"#)
        else { return false }

        for index in lines.indices {
            let line = lines[index]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard trimmedLine.hasSuffix(":") else { continue }
            let checkRange = NSRange(trimmedLine.startIndex..., in: trimmedLine)
            guard headerRegex.firstMatch(in: trimmedLine, range: checkRange) != nil else { continue }

            var next = index + 1
            while next < lines.count, lines[next].trimmingCharacters(in: .whitespaces).isEmpty {
                next += 1
            }
            guard next < lines.count else { continue }
            let indentCurrent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            let indentNext = lines[next].prefix(while: { $0 == " " || $0 == "\t" }).count
            if indentNext > indentCurrent { return true }
        }
        return false
    }

    private static let swiftSignals = [
        #"\bfunc\s+\w+\s*\("#,
        #"\blet\s+\w+\s*[:=]"#,
        #"\bvar\s+\w+\s*[:=]"#,
        #"\bstruct\s+\w+"#,
        #"\benum\s+\w+"#,
        #"\bprotocol\s+\w+"#,
        #"\bguard\s"#,
        #"->\s*\w"#,
        #"\bimport\s+(Foundation|SwiftUI|AppKit|UIKit|CopyCore)\b"#,
        #"\bprivate\b|\bpublic\b|\binternal\b"#,
    ]

    private static let javascriptSignals = [
        #"\bfunction\s+\w+\s*\("#,
        #"\bconst\s+\w+\s*="#,
        #"\blet\s+\w+\s*="#,
        #"=>"#,
        #"\bconsole\.log\s*\("#,
        #"\brequire\s*\("#,
        #"\bexport\s+(default\s+)?(function|const|class)\b"#,
        #"===|!=="#,
        #"\bthis\.\w+"#,
    ]

    private static let pythonSignals = [
        #"\bdef\s+\w+\s*\("#,
        #"\bimport\s+\w+"#,
        #"\bself\.\w+"#,
        #"\bprint\s*\("#,
        #"\belif\b"#,
        #"\bNone\b|\bTrue\b|\bFalse\b"#,
    ]

    // MARK: - HTML / CSS / shell (lighter heuristics)

    private static func isLikelyHTML(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("<!doctype html") { return true }
        var pairCount = 0
        for tag in htmlTags {
            guard lower.contains("<\(tag) ") || lower.contains("<\(tag)>") else { continue }
            guard lower.contains("</\(tag)>") else { continue }
            pairCount += 1
            if pairCount >= 2 { return true }
        }
        return false
    }

    private static let htmlTags = [
        "html", "head", "body", "div", "span", "p", "a", "ul", "ol", "li", "table", "tr", "td", "th",
        "h1", "h2", "h3", "h4", "h5", "h6", "script", "style", "button", "form", "section", "article",
        "nav", "header", "footer",
    ]

    /// `selector { prop: value; }` shape, gated on at least one recognizable CSS
    /// property name so a JS object literal (`{ color: "red" }`) doesn't false-positive
    /// — real JS with `const`/`function` is already caught by `detectScriptLanguage`
    /// before this ever runs.
    private static func isLikelyCSS(_ text: String) -> Bool {
        let shapePattern = #"[.#]?[A-Za-z][\w-]*(\s*[,>+~]\s*[.#]?[A-Za-z][\w-]*)*\s*\{[^{}]*:[^{}]*;[^{}]*\}"#
        guard text.range(of: shapePattern, options: .regularExpression) != nil else { return false }
        let lower = text.lowercased()
        return cssProperties.contains { lower.contains($0) }
    }

    private static let cssProperties = [
        "color", "background", "margin", "padding", "font", "display", "width", "height", "border",
        "position", "flex", "grid", "text-align", "line-height", "opacity", "transform", "transition",
        "z-index", "cursor", "overflow",
    ]

    /// Secondary shell signal for scripts without a shebang (e.g. pasted from the
    /// middle of a script, or a standalone command sequence): requires at least two
    /// independent hits from command names, `$(...)`/`${...}` expansion, or `&&`/`||`
    /// chaining.
    private static func isLikelyShellCommands(_ text: String) -> Bool {
        let signals = [
            #"(?m)^\s*(sudo\s+)?(cd|ls|grep|echo|export|curl|wget|chmod|mkdir|rm|mv|cp|git|npm|brew|docker|cat|source|ssh|tar|find)\b"#,
            #"\$\("#,
            #"\$\{\w+\}"#,
            #"&&|\|\|"#,
        ]
        return countMatches(text, patterns: signals) >= 2
    }

    // MARK: - Shared helpers

    /// Counts how many of `patterns` have at least one match anywhere in `text` (not
    /// total occurrences) — i.e. signal *variety*, which is what makes this resistant
    /// to prose that happens to repeat one coincidental keyword many times.
    private static func countMatches(_ text: String, patterns: [String]) -> Int {
        let range = NSRange(text.startIndex..., in: text)
        return patterns.reduce(0) { count, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return count }
            return regex.firstMatch(in: text, range: range) != nil ? count + 1 : count
        }
    }
}
