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
}
