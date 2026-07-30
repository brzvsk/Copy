import XCTest
@testable import CopyCore

final class OCRSnippetTests: XCTestCase {
    func testSnippetWindowsAroundAMatchInTheMiddle() throws {
        let text = String(repeating: "before ", count: 20) + "TARGET " + String(repeating: "after ", count: 20)
        let snippet = try XCTUnwrap(OCRSnippet.make(recognizedText: text, query: "target", context: 20))
        XCTAssertTrue(snippet.lowercased().contains("target"))
        XCTAssertTrue(snippet.hasPrefix("…"), "trimmed on the left should get a leading ellipsis")
        XCTAssertTrue(snippet.hasSuffix("…"), "trimmed on the right should get a trailing ellipsis")
        // Windowed, not the whole string.
        XCTAssertLessThan(snippet.count, text.count)
    }

    func testSnippetIsCaseAndDiacriticInsensitive() throws {
        let snippet = OCRSnippet.make(recognizedText: "Café Renseignements ouverts", query: "cafe")
        XCTAssertNotNil(snippet)
        XCTAssertTrue(snippet!.contains("Café"))
    }

    func testSnippetCollapsesNewlinesToOneLine() throws {
        let text = "line one\n\n   line two INVOICE line three\nline four"
        let snippet = try XCTUnwrap(OCRSnippet.make(recognizedText: text, query: "invoice"))
        XCTAssertFalse(snippet.contains("\n"))
        XCTAssertTrue(snippet.contains("INVOICE"))
    }

    func testMatchAtStartHasNoLeadingEllipsis() throws {
        let snippet = try XCTUnwrap(OCRSnippet.make(recognizedText: "RECEIPT total 42 dollars", query: "receipt", context: 40))
        XCTAssertFalse(snippet.hasPrefix("…"))
    }

    func testNoMatchReturnsNil() {
        XCTAssertNil(OCRSnippet.make(recognizedText: "nothing relevant here", query: "absent"))
        XCTAssertNil(OCRSnippet.make(recognizedText: "text", query: "   "))
    }
}
