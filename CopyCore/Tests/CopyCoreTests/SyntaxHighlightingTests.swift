import XCTest
@testable import CopyCore

final class SyntaxHighlightingTests: XCTestCase {
    // MARK: - Detection

    func testSwiftSnippetDetectsAsSwift() {
        let code = [
            "func greet(name: String) -> String {",
            "    let greeting = \"Hello, \\(name)!\"",
            "    // say hello",
            "    return greeting",
            "}",
        ].joined(separator: "\n")
        XCTAssertEqual(CodeDetector.detect(code), .swift)
    }

    func testJSONObjectDetectsAsJSON() {
        let json = [
            "{",
            "  \"name\": \"Copy\",",
            "  \"version\": 7,",
            "  \"features\": [\"clipboard\", \"sync\"]",
            "}",
        ].joined(separator: "\n")
        XCTAssertEqual(CodeDetector.detect(json), .json)
    }

    func testPythonSnippetDetectsAsPython() {
        let code = [
            "class Greeter:",
            "    def __init__(self, name):",
            "        self.name = name",
            "",
            "    def greet(self):",
            "        # say hello",
            "        message = f\"Hello, {self.name}!\"",
            "        print(message)",
            "        return message",
        ].joined(separator: "\n")
        XCTAssertEqual(CodeDetector.detect(code), .python)
    }

    func testJavaScriptSnippetDetectsAsJavaScript() {
        let code = [
            "function greet(name) {",
            "    const message = `Hello, ${name}!`;",
            "    console.log(message);",
            "    return message;",
            "}",
        ].joined(separator: "\n")
        XCTAssertEqual(CodeDetector.detect(code), .javascript)
    }

    /// Fix round 1 regression: a single inline code fragment quoted inside an ordinary
    /// sentence must not tip the whole sentence into "code" — the old ≥2-signal bar
    /// let `let ... =` (from the quoted fragment) plus a bare-word `guard` match (from
    /// "guard clause", plain English) add up to 2 even though this is overwhelmingly
    /// prose. This was a live false positive filed during review.
    func testInlineCodeFragmentQuotedInProseDoesNotDetectAsCode() {
        let text = "I added a guard clause: `guard let user = self.currentUser else "
            + "{ return } ` then removed the old check."
        XCTAssertNil(CodeDetector.detect(text))
    }

    /// Fix round 1 regression: `#!` followed by a space (a Markdown-ish aside, not an
    /// interpreter path) must not be mistaken for a shebang.
    func testMarkdownAsideStartingWithHashBangDoesNotDetectAsShell() {
        let text = "#! Important reminder\nDon't forget to renew the certificate before it expires."
        XCTAssertNil(CodeDetector.detect(text))
    }

    /// Fix round 1 regression: an unrelated word immediately before an unrelated
    /// `{ prop: value; }`-shaped clause, mid-sentence, must not be mistaken for a CSS
    /// rule — the selector portion must anchor to a line start, not match any trailing
    /// word wherever one happens to sit next to a brace.
    func testProseSentenceResemblingCSSDoesNotDetectAsCSS() {
        let text = "Color scheme { color: navy; accent: crimson; } was the designer's pick for the mockup."
        XCTAssertNil(CodeDetector.detect(text))
    }

    /// The most important test in this file: ordinary English prose must never be
    /// mistaken for code, however many curly braces of coincidence life throws at it.
    func testProseParagraphDoesNotDetectAsCode() {
        let prose = "Copy is a clipboard manager for macOS. It keeps track of everything "
            + "you copy so you can find it again later. The history is stored locally on "
            + "your Mac and never leaves the device unless you choose to sync it yourself."
        XCTAssertNil(CodeDetector.detect(prose))
    }

    func testEmptyAndWhitespaceTextDoesNotDetectAsCode() {
        XCTAssertNil(CodeDetector.detect(""))
        XCTAssertNil(CodeDetector.detect("   \n\t  "))
    }

    // MARK: - Tokenization

    func testSwiftTokensCoverKeywordStringAndComment() {
        let code = [
            "func greet(name: String) -> String {",
            "    let greeting = \"Hello, \\(name)!\"",
            "    // say hello",
            "    return greeting",
            "}",
        ].joined(separator: "\n")
        let tokens = SyntaxHighlighter.tokens(for: code, language: .swift)
        let ns = code as NSString

        let funcRange = ns.range(of: "func")
        XCTAssertTrue(tokens.contains { $0.range == funcRange && $0.kind == .keyword },
                       "expected a keyword token for 'func'")

        let stringRange = ns.range(of: "\"Hello, \\(name)!\"")
        XCTAssertTrue(tokens.contains { $0.range == stringRange && $0.kind == .string },
                       "expected a string token spanning the whole string literal")

        let commentRange = ns.range(of: "// say hello")
        XCTAssertTrue(tokens.contains { $0.range == commentRange && $0.kind == .comment },
                       "expected a comment token for the line comment")
    }

    func testJSONTokensCoverStringAndNumber() {
        let json = [
            "{",
            "  \"name\": \"Copy\",",
            "  \"version\": 7,",
            "  \"features\": [\"clipboard\", \"sync\"]",
            "}",
        ].joined(separator: "\n")
        let tokens = SyntaxHighlighter.tokens(for: json, language: .json)
        let ns = json as NSString

        let keyRange = ns.range(of: "\"name\"")
        XCTAssertTrue(tokens.contains { $0.range == keyRange && $0.kind == .string },
                       "expected a string token for the \"name\" key")

        let numberRange = ns.range(of: "7")
        XCTAssertTrue(tokens.contains { $0.range == numberRange && $0.kind == .number },
                       "expected a number token for the version value")
    }

    func testTokensAreNonOverlappingAndSorted() {
        let code = [
            "func greet(name: String) -> String {",
            "    let greeting = \"Hello, \\(name)!\"",
            "    // say hello",
            "    return greeting",
            "}",
        ].joined(separator: "\n")
        let tokens = SyntaxHighlighter.tokens(for: code, language: .swift)

        var previousEnd = 0
        for token in tokens {
            XCTAssertGreaterThanOrEqual(token.range.location, previousEnd,
                                         "tokens must be sorted and non-overlapping")
            previousEnd = token.range.location + token.range.length
        }
    }

    func testUnknownLanguageProducesNoTokens() {
        XCTAssertEqual(SyntaxHighlighter.tokens(for: "func foo() {}", language: .unknown), [])
    }

    func testEmptyTextProducesNoTokens() {
        XCTAssertEqual(SyntaxHighlighter.tokens(for: "", language: .swift), [])
    }
}
