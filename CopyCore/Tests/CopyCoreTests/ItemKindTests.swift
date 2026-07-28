import XCTest
@testable import CopyCore

final class ItemKindTests: XCTestCase {
    func testLinkDetection() {
        XCTAssertEqual(ItemKind.forText("https://example.com/page"), .link)
        XCTAssertEqual(ItemKind.forText("http://example.com"), .link)
        XCTAssertEqual(ItemKind.forText("  https://example.com  "), .link)
        XCTAssertEqual(ItemKind.forText("check https://example.com out"), .text)
        XCTAssertEqual(ItemKind.forText("hello"), .text)
        XCTAssertEqual(ItemKind.forText("ftp://example.com"), .text)
        XCTAssertEqual(ItemKind.forText(""), .text)
    }
}
