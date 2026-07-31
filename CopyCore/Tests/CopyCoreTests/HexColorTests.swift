import XCTest
@testable import CopyCore

final class HexColorTests: XCTestCase {
    func testAcceptsSixDigitWithHash() {
        XCTAssertEqual(HexColor.normalized("#4C9DFF"), "#4C9DFF")
    }
    func testAcceptsSixDigitWithoutHashAndLowercase() {
        XCTAssertEqual(HexColor.normalized("4c9dff"), "#4C9DFF")
    }
    func testExpandsShorthand() {
        XCTAssertEqual(HexColor.normalized("#abc"), "#AABBCC")
    }
    func testTrimsWhitespace() {
        XCTAssertEqual(HexColor.normalized("  #FFFFFF \n"), "#FFFFFF")
    }
    func testRejectsNonHexAndWrongLength() {
        XCTAssertNil(HexColor.normalized("hello"))
        XCTAssertNil(HexColor.normalized("#12345"))
        XCTAssertNil(HexColor.normalized("#4C9DFF is the accent"))
        XCTAssertNil(HexColor.normalized("#GGGGGG"))
        XCTAssertNil(HexColor.normalized(""))
    }

    func testIsColorTextClassification() {
        XCTAssertTrue(HexColor.isColorText("#123456"))   // with # → color even if all digits
        XCTAssertTrue(HexColor.isColorText("4C9DFF"))    // bare, has letters → color
        XCTAssertTrue(HexColor.isColorText("abc"))       // bare shorthand, letters → color
        XCTAssertTrue(HexColor.isColorText("  #FFFFFF "))
        XCTAssertFalse(HexColor.isColorText("123456"))   // bare, all digits → stays text
        XCTAssertFalse(HexColor.isColorText("hello"))
        XCTAssertFalse(HexColor.isColorText("#4C9DFF is nice"))
    }
}
