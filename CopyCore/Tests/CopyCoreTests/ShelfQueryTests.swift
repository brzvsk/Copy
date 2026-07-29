import XCTest
@testable import CopyCore

final class ShelfQueryTests: XCTestCase {
    func testScopeKindMapping() {
        XCTAssertNil(ShelfScope.all.kinds)
        XCTAssertEqual(ShelfScope.text.kinds, [.text, .richText])
        XCTAssertEqual(ShelfScope.images.kinds, [.image])
        XCTAssertEqual(ShelfScope.links.kinds, [.link])
        XCTAssertEqual(ShelfScope.files.kinds, [.file])
        XCTAssertEqual(ShelfScope.allCases.map(\.title), ["All", "Text", "Images", "Links", "Files"])
    }

    func testRecentItemsFiltersByKind() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("plain note"))
        _ = try store.save(CapturedItem(kind: .link, plainText: "https://example.com",
                                        hashData: Data("https://example.com".utf8),
                                        representations: [CapturedRepresentation(uti: "public.utf8-plain-text", data: Data("https://example.com".utf8))],
                                        sourceBundleID: nil, sourceAppName: nil))
        XCTAssertEqual(try store.recentItems(kinds: ShelfScope.links.kinds, limit: 10).map(\.kind), [.link])
        XCTAssertEqual(try store.recentItems(kinds: ShelfScope.text.kinds, limit: 10).map(\.plainText), ["plain note"])
        XCTAssertEqual(try store.recentItems(kinds: nil, limit: 10).count, 2)
    }

    func testSearchFiltersByKind() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("example text"))
        _ = try store.save(CapturedItem(kind: .link, plainText: "https://example.com",
                                        hashData: Data("l".utf8),
                                        representations: [CapturedRepresentation(uti: "public.utf8-plain-text", data: Data("https://example.com".utf8))],
                                        sourceBundleID: nil, sourceAppName: nil))
        XCTAssertEqual(try store.search("example", kinds: ShelfScope.links.kinds).map(\.kind), [.link])
        XCTAssertEqual(try store.search("example", kinds: nil).count, 2)
    }

    func testObserveRecentFiresOnChange() throws {
        let store = try makeTempStore()
        let initial = expectation(description: "initial")
        let afterInsert = expectation(description: "after insert")
        var deliveries: [[ClipItem]] = []
        let token = store.observeRecent(limit: 10, onError: { XCTFail("\($0)") }) { items in
            deliveries.append(items)
            if deliveries.count == 1 { initial.fulfill() }
            if deliveries.count == 2 { afterInsert.fulfill() }
        }
        wait(for: [initial], timeout: 5)
        _ = try store.save(makeText("observed"))
        wait(for: [afterInsert], timeout: 5)
        token.cancel()
        XCTAssertEqual(deliveries[0].count, 0)
        XCTAssertEqual(deliveries[1].map(\.plainText), ["observed"])
    }
}
