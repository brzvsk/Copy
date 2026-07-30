import XCTest
@testable import CopyCore

final class ItemStoreSearchTests: XCTestCase {
    func testSearchMatchesPrefix() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("SwiftUI clipboard manager"))
        _ = try store.save(makeText("grocery list"))
        let hits = try store.search("clip")
        XCTAssertEqual(hits.map(\.plainText), ["SwiftUI clipboard manager"])
    }

    func testSearchEmptyQueryReturnsEmpty() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("anything"))
        XCTAssertEqual(try store.search("").count, 0)
    }

    func testDeleteRemovesItemAndRepresentations() throws {
        let store = try makeTempStore()
        let saved = try store.save(makeText("to delete"))
        try store.delete(itemID: saved.id!)
        XCTAssertEqual(try store.recentItems(limit: 10).count, 0)
        XCTAssertEqual(try store.representations(forItemID: saved.id!).count, 0)
        XCTAssertEqual(try store.search("delete").count, 0)
    }

    func testClearHistoryKeepsFavorites() throws {
        let store = try makeTempStore()
        let fav = try store.save(makeText("keep me"))
        _ = try store.save(makeText("toss me"))
        try store.setFavorite(itemID: fav.id!, true)
        try store.clearHistory(keepFavorites: true)
        let remaining = try store.recentItems(limit: 10)
        XCTAssertEqual(remaining.map(\.plainText), ["keep me"])
        XCTAssertTrue(remaining[0].isFavorite)
    }

    func testTouchMovesToFront() throws {
        let store = try makeTempStore()
        let a = try store.save(makeText("a"), now: Date(timeIntervalSince1970: 1000))
        _ = try store.save(makeText("b"), now: Date(timeIntervalSince1970: 2000))
        try store.touch(itemID: a.id!, now: Date(timeIntervalSince1970: 3000))
        XCTAssertEqual(try store.recentItems(limit: 10).map(\.plainText), ["a", "b"])
    }

    func testSearchScopedToPinboardReturnsOnlyMember() throws {
        let (store, pinboards) = try makeTempStores()
        let board = try pinboards.create(name: "Board", symbol: "pin")
        let a = try store.save(makeText("widget alpha"))
        let b = try store.save(makeText("widget beta"))
        try pinboards.add(itemID: a.id!, to: board.id!)

        let scoped = try store.search("widget", pinboardID: board.id!)
        XCTAssertEqual(scoped.map(\.plainText), ["widget alpha"])

        let global = try store.search("widget", pinboardID: nil)
        XCTAssertEqual(Set(global.map(\.plainText)), Set(["widget alpha", "widget beta"]))
    }

    func testSearchScopedToPinboardExcludesNonMemberMatch() throws {
        let (store, pinboards) = try makeTempStores()
        let board = try pinboards.create(name: "Board", symbol: "pin")
        _ = try store.save(makeText("gadget outside"))

        XCTAssertEqual(try store.search("gadget", pinboardID: board.id!).count, 0)
    }

    func testSearchScopedToPinboardComposesWithKindsFilter() throws {
        let (store, pinboards) = try makeTempStores()
        let board = try pinboards.create(name: "Board", symbol: "pin")
        let text = try store.save(makeText("marker note"))
        let linkURL = "https://marker.example.com"
        let link = try store.save(CapturedItem(
            kind: .link, plainText: linkURL, hashData: Data(linkURL.utf8),
            representations: [CapturedRepresentation(uti: "public.utf8-plain-text", data: Data(linkURL.utf8))],
            sourceBundleID: "com.test.app", sourceAppName: "TestApp"))
        try pinboards.add(itemID: text.id!, to: board.id!)
        try pinboards.add(itemID: link.id!, to: board.id!)

        let scopedText = try store.search("marker", kinds: [.text], pinboardID: board.id!)
        XCTAssertEqual(scopedText.map(\.plainText), ["marker note"])
    }
}
