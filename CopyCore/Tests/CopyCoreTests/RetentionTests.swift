import XCTest
@testable import CopyCore

final class RetentionTests: XCTestCase {
    func testChunkedDeletesFor1200Items() throws {
        let store = try makeTempStore()

        // Save 1,200 distinct text items
        for i in 0..<1200 {
            let text = "item-\(i)"
            _ = try store.save(makeText(text))
        }

        let beforeClear = try store.recentItems(limit: 5000)
        XCTAssertEqual(beforeClear.count, 1200, "Should have saved 1200 items")

        // Clear all (no favorites to preserve)
        try store.clearHistory(keepFavorites: false)

        let afterClear = try store.recentItems(limit: 5000)
        XCTAssertEqual(afterClear.count, 0, "clearHistory should delete all items across chunks")
    }

    func testPruneByDateSparesOldUnprotectedOnly() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopyTests-\(UUID().uuidString)")
        let dbm = try DatabaseManager(directory: dir)
        let store = ItemStore(writer: dbm.writer, blobs: BlobStore(directory: dbm.blobsDirectory))
        let pinboardStore = PinboardStore(writer: dbm.writer)

        let oldDate = Date(timeIntervalSince1970: 1000)
        let cutoffDate = Date(timeIntervalSince1970: 2000)
        let newDate = Date(timeIntervalSince1970: 3000)

        // Create 4 items: 3 old, 1 new
        let oldUnprotected = try store.save(makeText("old-unprotected"), now: oldDate)
        let oldFavorite = try store.save(makeText("old-favorite"), now: oldDate)
        let oldPinboardMember = try store.save(makeText("old-pinboard"), now: oldDate)
        let newItem = try store.save(makeText("new"), now: newDate)

        // Mark one old item as favorite
        try store.setFavorite(itemID: oldFavorite.id!, true)

        // Add one old item to a pinboard
        let pinboard = try pinboardStore.create(name: "Board", symbol: "star")
        try pinboardStore.add(itemID: oldPinboardMember.id!, to: pinboard.id!)

        // Prune items older than cutoff
        let deletedCount = try store.prune(olderThan: cutoffDate, maxItems: nil)

        XCTAssertEqual(deletedCount, 1, "Should delete only the unprotected old item")

        let remaining = try store.recentItems(limit: 100)
        XCTAssertEqual(remaining.count, 3, "Favorite, pinboard member, and new item should remain")
    }

    func testPruneByCountKeepsNewest() throws {
        let store = try makeTempStore()

        // Create 5 items with different timestamps
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)
        let t3 = Date(timeIntervalSince1970: 3000)
        let t4 = Date(timeIntervalSince1970: 4000)
        let t5 = Date(timeIntervalSince1970: 5000)

        let item1 = try store.save(makeText("1"), now: t1)
        let item2 = try store.save(makeText("2"), now: t2)
        let item3 = try store.save(makeText("3"), now: t3)
        let item4 = try store.save(makeText("4"), now: t4)
        let item5 = try store.save(makeText("5"), now: t5)

        // Prune, keeping only 2 newest
        let deletedCount = try store.prune(olderThan: nil, maxItems: 2)

        XCTAssertEqual(deletedCount, 3, "Should delete 3 oldest items, keeping 2 newest")

        let remaining = try store.recentItems(limit: 100)
        XCTAssertEqual(remaining.count, 2)
        XCTAssertEqual(remaining[0].plainText, "5")
        XCTAssertEqual(remaining[1].plainText, "4")
    }

    func testPruneNilNilNoop() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("item1"))
        _ = try store.save(makeText("item2"))

        let deletedCount = try store.prune(olderThan: nil, maxItems: nil)

        XCTAssertEqual(deletedCount, 0, "prune with both params nil should be a no-op")

        let remaining = try store.recentItems(limit: 100)
        XCTAssertEqual(remaining.count, 2, "Items should remain unchanged")
    }

    func testSetLinkTitleSearchable() throws {
        let store = try makeTempStore()
        let item = try store.save(makeText("just text"))

        // Set link title
        try store.setLinkTitle(itemID: item.id!, "Example Site")

        // Search for the link title
        let results = try store.search("Example")
        XCTAssertEqual(results.count, 1, "Should find item by link title via FTS")
        XCTAssertEqual(results[0].id, item.id)
    }

    func testSetFaviconUpserts() throws {
        let store = try makeTempStore()
        let item = try store.save(makeText("website"))

        let pngData1 = Data([0x89, 0x50, 0x4E, 0x47])
        let pngData2 = Data([0xFF, 0xFE, 0xFD, 0xFC])

        // Set favicon first time
        try store.setFavicon(itemID: item.id!, pngData: pngData1)
        let favicon1 = try store.favicon(forItemID: item.id!)
        XCTAssertEqual(favicon1, pngData1)

        // Set favicon second time (should replace)
        try store.setFavicon(itemID: item.id!, pngData: pngData2)
        let favicon2 = try store.favicon(forItemID: item.id!)
        XCTAssertEqual(favicon2, pngData2, "Second favicon should replace first")

        // Verify only one favicon representation exists
        let reps = try store.representations(forItemID: item.id!)
        let faviconReps = reps.filter { $0.uti == "sk.brzv.copy.favicon" }
        XCTAssertEqual(faviconReps.count, 1, "Should have exactly one favicon representation")
    }

    func testSetFaviconCleansOrphanedBlobs() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopyTests-\(UUID().uuidString)")
        let dbm = try DatabaseManager(directory: dir)
        let store = ItemStore(writer: dbm.writer, blobs: BlobStore(directory: dbm.blobsDirectory))

        let item = try store.save(makeText("website"))

        // Create two large PNG data sets (>65,536 bytes to force blob storage)
        let largePng1 = Data(repeating: 0xFF, count: 100_000)
        let largePng2 = Data(repeating: 0xEE, count: 100_000)

        // Set favicon first time (creates blob)
        try store.setFavicon(itemID: item.id!, pngData: largePng1)
        var blobFiles = try FileManager.default.contentsOfDirectory(atPath: dbm.blobsDirectory.path)
        XCTAssertEqual(blobFiles.count, 1, "Should have 1 blob file after first setFavicon")

        // Set favicon second time (should replace and clean old blob)
        try store.setFavicon(itemID: item.id!, pngData: largePng2)
        blobFiles = try FileManager.default.contentsOfDirectory(atPath: dbm.blobsDirectory.path)
        XCTAssertEqual(blobFiles.count, 1, "Should still have exactly 1 blob file after replacement")

        // Verify the new data is returned
        let favicon = try store.favicon(forItemID: item.id!)
        XCTAssertEqual(favicon, largePng2, "Should return the second favicon data")
    }
}
