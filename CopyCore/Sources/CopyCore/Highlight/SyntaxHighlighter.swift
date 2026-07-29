import Foundation

/// Semantic category of a highlighted span. Anything not covered by a returned
/// `HighlightToken` is implicitly `.plain` — callers only need to color the ranges
/// they're given and leave the rest at the default text color.
public enum TokenKind: Equatable, Sendable {
    case keyword
    case string
    case comment
    case number
    case type
    case plain
}

/// A single highlighted span. `range` is an `NSRange` over the UTF-16 view of the
/// text that was tokenized — the same view `NSString` uses — which keeps slicing back
/// to substrings a one-liner (`(text as NSString).substring(with: range)`) for callers
/// bridging into `Text`/`AttributedString` on the app side.
public struct HighlightToken: Equatable {
    public let range: NSRange
    public let kind: TokenKind

    public init(range: NSRange, kind: TokenKind) {
        self.range = range
        self.kind = kind
    }
}

/// Regex/scanner-based syntax highlighter with no third-party dependency. Each
/// language is a short, ordered list of rules (comments and strings first, since they
/// can contain characters that would otherwise look like keywords or numbers; plain
/// identifiers/types last), applied to a flat per-character "canvas" so overlaps
/// resolve to a single winner — whichever higher-priority rule claimed a character
/// first — without ever comparing matches against each other pairwise.
public enum SyntaxHighlighter {
    /// Tokenizes `text` for `language` into non-overlapping, location-sorted spans.
    ///
    /// Runs in O(text length × rule count): each rule's regex sweeps `text` once via
    /// `NSRegularExpression.enumerateMatches`, and matches are written into the canvas
    /// rather than checked against every other match, so there's no O(n²) blowup on
    /// large input. Callers should still pass a capped prefix for very large pastes —
    /// this function doesn't itself decide how much of an item's text to highlight.
    public static func tokens(for text: String, language: CodeLanguage) -> [HighlightToken] {
        guard !text.isEmpty, let grammar = grammars[language] else { return [] }
        let length = (text as NSString).length
        guard length > 0 else { return [] }

        var canvas = [TokenKind?](repeating: nil, count: length)
        let fullRange = NSRange(location: 0, length: length)
        for rule in grammar {
            rule.regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let match, match.range.location != NSNotFound else { return }
                claim(match.range, as: rule.kind, in: &canvas)
            }
        }
        return mergeRuns(canvas)
    }

    private static func claim(_ range: NSRange, as kind: TokenKind, in canvas: inout [TokenKind?]) {
        let start = max(0, range.location)
        let end = min(canvas.count, range.location + range.length)
        guard start < end else { return }
        for i in start..<end where canvas[i] == nil {
            canvas[i] = kind
        }
    }

    private static func mergeRuns(_ canvas: [TokenKind?]) -> [HighlightToken] {
        var tokens: [HighlightToken] = []
        var index = 0
        while index < canvas.count {
            guard let kind = canvas[index] else { index += 1; continue }
            var end = index + 1
            while end < canvas.count, canvas[end] == kind { end += 1 }
            tokens.append(HighlightToken(range: NSRange(location: index, length: end - index), kind: kind))
            index = end
        }
        return tokens
    }

    // MARK: - Rule / grammar plumbing

    private struct Rule {
        let kind: TokenKind
        let regex: NSRegularExpression
    }

    /// Compiles `(kind, pattern)` pairs into `Rule`s, silently dropping any pattern
    /// that fails to compile (asserting in debug so a typo is caught during
    /// development) rather than crashing the app — a bad built-in pattern should
    /// degrade to "that construct stays unhighlighted," never a runtime trap.
    private static func makeGrammar(_ specs: [(TokenKind, String)]) -> [Rule] {
        specs.compactMap { kind, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                assertionFailure("Invalid built-in highlight pattern: \(pattern)")
                return nil
            }
            return Rule(kind: kind, regex: regex)
        }
    }

    private static func keywordPattern(_ keywords: [String]) -> String {
        #"\b(?:"# + keywords.joined(separator: "|") + #")\b"#
    }

    private static let quote3 = "\"\"\""
    private static let numberPattern = #"\b0x[0-9a-fA-F]+\b|\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#
    private static let doubleQuotedString = #""(?:\\.|[^"\\\n])*""#
    private static let singleQuotedString = #"'(?:\\.|[^'\\\n])*'"#
    private static let typePattern = #"\b[A-Z][A-Za-z0-9_]*\b"#

    private static let grammars: [CodeLanguage: [Rule]] = [
        .swift: swiftGrammar,
        .javascript: javascriptGrammar,
        .python: pythonGrammar,
        .json: jsonGrammar,
        .shell: shellGrammar,
        .html: htmlGrammar,
        .css: cssGrammar,
    ]

    // MARK: - Swift

    private static let swiftKeywords = [
        "func", "let", "var", "struct", "class", "enum", "protocol", "extension", "import", "guard",
        "if", "else", "switch", "case", "default", "return", "break", "continue", "fallthrough", "for",
        "while", "repeat", "do", "catch", "try", "throw", "throws", "rethrows", "async", "await", "in",
        "where", "is", "as", "nil", "true", "false", "self", "Self", "super", "init", "deinit",
        "subscript", "typealias", "associatedtype", "public", "private", "internal", "fileprivate",
        "open", "static", "final", "override", "mutating", "nonmutating", "lazy", "weak", "unowned",
        "inout", "some", "any", "indirect", "defer", "operator", "actor",
    ]

    private static let swiftGrammar: [Rule] = makeGrammar([
        (.comment, #"/\*[\s\S]*?\*/"#),
        (.comment, #"//[^\n]*"#),
        (.string, quote3 + #"[\s\S]*?"# + quote3),
        (.string, doubleQuotedString),
        (.number, numberPattern),
        (.keyword, keywordPattern(swiftKeywords)),
        (.type, typePattern),
    ])

    // MARK: - JavaScript

    private static let javascriptKeywords = [
        "function", "const", "let", "var", "class", "extends", "import", "export", "from", "default",
        "return", "if", "else", "switch", "case", "break", "continue", "for", "while", "do", "try",
        "catch", "finally", "throw", "new", "this", "typeof", "instanceof", "in", "of", "async",
        "await", "yield", "null", "undefined", "true", "false", "void", "delete", "static", "get",
        "set", "super", "constructor",
    ]

    private static let javascriptGrammar: [Rule] = makeGrammar([
        (.comment, #"/\*[\s\S]*?\*/"#),
        (.comment, #"//[^\n]*"#),
        (.string, #"`(?:\\.|[^`\\])*`"#),
        (.string, doubleQuotedString),
        (.string, singleQuotedString),
        (.number, numberPattern),
        (.keyword, keywordPattern(javascriptKeywords)),
        (.type, typePattern),
    ])

    // MARK: - Python

    private static let pythonKeywords = [
        "def", "class", "import", "from", "as", "return", "if", "elif", "else", "for", "while", "try",
        "except", "finally", "with", "lambda", "yield", "pass", "break", "continue", "raise", "and",
        "or", "not", "in", "is", "None", "True", "False", "self", "global", "nonlocal", "assert", "del",
        "async", "await",
    ]

    private static let pythonGrammar: [Rule] = makeGrammar([
        (.comment, #"#[^\n]*"#),
        (.string, quote3 + #"[\s\S]*?"# + quote3),
        (.string, "'''" + #"[\s\S]*?"# + "'''"),
        (.string, doubleQuotedString),
        (.string, singleQuotedString),
        (.number, numberPattern),
        (.keyword, keywordPattern(pythonKeywords)),
        (.type, typePattern),
    ])

    // MARK: - JSON

    private static let jsonGrammar: [Rule] = makeGrammar([
        (.string, doubleQuotedString),
        (.number, #"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?"#),
        (.keyword, #"\b(?:true|false|null)\b"#),
    ])

    // MARK: - Shell

    private static let shellKeywords = [
        "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac",
        "function", "return", "exit", "export", "local", "readonly", "in", "select", "echo", "cd",
        "source", "alias", "unset", "shift", "break", "continue",
    ]

    private static let shellGrammar: [Rule] = makeGrammar([
        (.comment, #"#[^\n]*"#),
        (.string, doubleQuotedString),
        (.string, singleQuotedString),
        (.number, numberPattern),
        (.keyword, keywordPattern(shellKeywords)),
    ])

    // MARK: - HTML (lighter coverage)

    private static let htmlGrammar: [Rule] = makeGrammar([
        (.comment, #"<!--[\s\S]*?-->"#),
        (.string, doubleQuotedString),
        (.string, singleQuotedString),
        (.keyword, #"</?[a-zA-Z][a-zA-Z0-9]*"#),
    ])

    // MARK: - CSS (lighter coverage)

    private static let cssGrammar: [Rule] = makeGrammar([
        (.comment, #"/\*[\s\S]*?\*/"#),
        (.string, doubleQuotedString),
        (.string, singleQuotedString),
        (.number, #"\b\d+(?:\.\d+)?\b"#),
    ])
}
