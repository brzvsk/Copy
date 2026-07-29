import XCTest
@testable import CopyCore

final class ShelfSelectionTests: XCTestCase {
    let order = ["a", "b", "c", "d", "e"]

    func testClickSelectsSingle() {
        var sel = ShelfSelection()
        sel.click("b")
        XCTAssertEqual(sel.selected, ["b"])
        XCTAssertEqual(sel.primary, "b")
        sel.click("d")
        XCTAssertEqual(sel.selected, ["d"])
    }

    func testCommandClickToggles() {
        var sel = ShelfSelection()
        sel.click("a")
        sel.commandClick("c")
        XCTAssertEqual(sel.selected, ["a", "c"])
        XCTAssertEqual(sel.primary, "c")
        sel.commandClick("c")
        XCTAssertEqual(sel.selected, ["a"])
        XCTAssertEqual(sel.primary, "a")
    }

    func testShiftClickSelectsRange() {
        var sel = ShelfSelection()
        sel.click("b")
        sel.shiftClick("d", in: order)
        XCTAssertEqual(sel.selected, ["b", "c", "d"])
        XCTAssertEqual(sel.primary, "b")
        sel.shiftClick("a", in: order)
        XCTAssertEqual(sel.selected, ["a", "b"])
    }

    func testMoveCollapsesAndClamps() {
        var sel = ShelfSelection()
        sel.click("b")
        sel.commandClick("d")
        sel.move(1, in: order)
        XCTAssertEqual(sel.selected, ["e"])
        XCTAssertEqual(sel.primary, "e")
        sel.move(1, in: order)
        XCTAssertEqual(sel.primary, "e") // clamped at end
        sel.move(-10, in: order)
        XCTAssertEqual(sel.primary, "a")
    }

    func testMoveWithEmptySelectionPicksFirst() {
        var sel = ShelfSelection()
        sel.move(1, in: order)
        XCTAssertEqual(sel.primary, "a")
        XCTAssertEqual(sel.selected, ["a"])
    }

    func testOrderedSelection() {
        var sel = ShelfSelection()
        sel.click("d")
        sel.commandClick("a")
        sel.commandClick("c")
        XCTAssertEqual(sel.orderedSelection(in: order), ["a", "c", "d"])
    }

    func testPruneDropsVanishedAndReanchorsPrimary() {
        var sel = ShelfSelection()
        sel.click("b")
        sel.commandClick("c")
        sel.prune(existing: ["a", "c", "d", "e"], order: ["a", "c", "d", "e"])
        XCTAssertEqual(sel.selected, ["c"])
        XCTAssertEqual(sel.primary, "c")
        sel.prune(existing: [], order: [])
        XCTAssertNil(sel.primary)
        XCTAssertTrue(sel.selected.isEmpty)
    }
}
