import XCTest
@testable import CopyCore

final class PageWindowTests: XCTestCase {
    func testStartsAtOnePage() {
        XCTAssertEqual(PageWindow().limit, 100)
        XCTAssertEqual(PageWindow(pageSize: 40).limit, 40)
    }

    func testDoesNotGrowWhileScrollingThroughTheLoadedRows() {
        var window = PageWindow()
        XCTAssertFalse(window.growIfNeeded(visibleIndex: 0, loadedCount: 100))
        XCTAssertFalse(window.growIfNeeded(visibleIndex: 50, loadedCount: 100))
        // 79 is one row short of the lookahead boundary (100 - 20).
        XCTAssertFalse(window.growIfNeeded(visibleIndex: 79, loadedCount: 100))
        XCTAssertEqual(window.limit, 100)
    }

    func testGrowsOnceWithinLookaheadOfTheEnd() {
        var window = PageWindow()
        XCTAssertTrue(window.growIfNeeded(visibleIndex: 80, loadedCount: 100))
        XCTAssertEqual(window.limit, 300)
    }

    /// The bug this guards: cards keep appearing while the wider fetch is still in flight,
    /// so without a re-entrancy guard the window would balloon by a page per card revealed.
    func testIgnoresRepeatCallsUntilTheWiderFetchLands() {
        var window = PageWindow()
        XCTAssertTrue(window.growIfNeeded(visibleIndex: 80, loadedCount: 100))
        for index in 81..<100 {
            XCTAssertFalse(window.growIfNeeded(visibleIndex: index, loadedCount: 100))
        }
        XCTAssertEqual(window.limit, 300)

        // The 300-row fetch lands; scrolling on grows the window again.
        XCTAssertTrue(window.growIfNeeded(visibleIndex: 280, loadedCount: 300))
        XCTAssertEqual(window.limit, 500)
    }

    /// A short page means the query ran out of rows, so the shelf stops re-querying instead
    /// of widening forever against an exhausted history.
    func testStopsGrowingOnceTheQueryIsExhausted() {
        var window = PageWindow()
        XCTAssertTrue(window.growIfNeeded(visibleIndex: 99, loadedCount: 100))
        XCTAssertEqual(window.limit, 300)
        // Only 250 rows existed, so the widened fetch came back short.
        XCTAssertFalse(window.growIfNeeded(visibleIndex: 249, loadedCount: 250))
        XCTAssertEqual(window.limit, 300)
    }

    func testResetNarrowsBackToOnePage() {
        var window = PageWindow()
        XCTAssertTrue(window.growIfNeeded(visibleIndex: 90, loadedCount: 100))
        XCTAssertEqual(window.limit, 300)
        window.reset()
        XCTAssertEqual(window.limit, 100)
    }

    func testEmptyResultNeverGrows() {
        var window = PageWindow()
        XCTAssertFalse(window.growIfNeeded(visibleIndex: 0, loadedCount: 0))
        XCTAssertEqual(window.limit, 100)
    }

    /// The whole point of the fix: enough growth steps reach past any fixed floor. 1044 rows
    /// is this history's real size, which a fixed 100-row window cut off after two days.
    func testWalksPastTheOldFixedCeiling() {
        var window = PageWindow()
        var loaded = 0
        var fetches = 0
        while loaded < 1044, fetches < 100 {
            loaded = min(window.limit, 1044)
            fetches += 1
            _ = window.growIfNeeded(visibleIndex: loaded - 1, loadedCount: loaded)
        }
        XCTAssertEqual(loaded, 1044)
        XCTAssertLessThanOrEqual(fetches, 7)
    }
}
