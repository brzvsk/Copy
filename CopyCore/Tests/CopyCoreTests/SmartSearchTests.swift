import XCTest
@testable import CopyCore

final class SmartSearchTests: XCTestCase {
    func testToFilterMapsEveryFacet() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var query = SearchQuery()
        query.add(.app(bundleID: "com.apple.Safari", name: "Safari"))
        query.add(.type(.links))
        query.add(.type(.images))
        query.add(.favorites)
        query.add(.pinboard(id: 3, name: "Work"))
        query.add(.date(.last7))
        query.text = "movement"

        let filter = query.toFilter(now: now)
        XCTAssertEqual(filter.text, "movement")
        XCTAssertEqual(filter.appBundleID, "com.apple.Safari")
        XCTAssertEqual(filter.kinds, [.link, .image])
        XCTAssertTrue(filter.favoritesOnly)
        XCTAssertEqual(filter.pinboardIDs, [3])
        XCTAssertEqual(filter.dateRange, SearchDate.last7.interval(now: now))
    }

    func testAddReplacesSingleValuedFacets() {
        var query = SearchQuery()
        query.add(.app(bundleID: "a", name: "A"))
        query.add(.app(bundleID: "b", name: "B"))          // replaces the first app
        query.add(.date(.today))
        query.add(.date(.last30))                            // replaces the first date
        query.add(.type(.links))
        query.add(.type(.links))                             // deduped

        XCTAssertEqual(query.tokens.count, 3)
        XCTAssertEqual(query.toFilter().appBundleID, "b")
        XCTAssertTrue(query.tokens.contains(.date(.last30)))
        XCTAssertFalse(query.tokens.contains(.date(.today)))
    }

    func testSuggestionsRankTypeThenAppThenDate() {
        // Prefix "l": Link (type), Linear (app), Last 7/30/... (date) — types first, then
        // apps, then dates, matching the reference dropdown.
        let apps = [AppUsage(bundleID: "com.linear", name: "Linear", count: 5)]
        let suggestions = searchSuggestions(prefix: "l", apps: apps, pinboards: [], query: SearchQuery())
        XCTAssertEqual(suggestions.first, .type(.links))
        XCTAssertEqual(suggestions.dropFirst().first, .app(bundleID: "com.linear", name: "Linear"))
        XCTAssertTrue(suggestions.contains(.date(.last7)))
        XCTAssertFalse(suggestions.contains(.date(.today)))  // "Today" doesn't start with "l"
    }

    func testSuggestionsExcludeAlreadyPresentAndSingleValued() {
        let apps = [AppUsage(bundleID: "com.safari", name: "Safari", count: 9)]
        var query = SearchQuery()
        query.add(.app(bundleID: "com.other", name: "Other"))   // an app already chosen
        // "s" would match Safari, but an app token already exists, so no app suggestions.
        let suggestions = searchSuggestions(prefix: "s", apps: apps, pinboards: [], query: query)
        XCTAssertFalse(suggestions.contains { $0.appBundleID != nil })
    }

    func testEmptyPrefixYieldsNoSuggestions() {
        let apps = [AppUsage(bundleID: "com.safari", name: "Safari", count: 9)]
        XCTAssertTrue(searchSuggestions(prefix: "  ", apps: apps, pinboards: [], query: SearchQuery()).isEmpty)
    }

    func testDateIntervalsAreCalendarDayRanges() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14 22:13:20 UTC
        let today = SearchDate.today.interval(now: now, calendar: cal)
        XCTAssertEqual(today.duration, 86_400, accuracy: 1)   // exactly one day
        let last7 = SearchDate.last7.interval(now: now, calendar: cal)
        XCTAssertEqual(last7.duration, 7 * 86_400, accuracy: 1)
        XCTAssertEqual(today.end, last7.end)                  // both end at start-of-tomorrow
    }
}
