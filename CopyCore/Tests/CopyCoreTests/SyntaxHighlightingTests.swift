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
