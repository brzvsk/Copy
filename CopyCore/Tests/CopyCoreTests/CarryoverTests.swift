import XCTest
@testable import CopyCore

final class CarryoverTests: XCTestCase {
    private func makeBlobItem(_ payload: UInt8, hashSeed: String) -> CapturedItem {
        CapturedItem(kind: .image, plainText: "Image", hashData: Data(hashSeed.utf8),
                     representations: [CapturedRepresentation(uti: "public.png",
                                                              data: Data(repeating: payload, count: 100_000))],
                     sourceBundleID: nil, sourceAppName: nil)
    }

    func testClearHistoryRemovesBlobFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopyTests-\(UUID().uuidString)")
        let dbm = try DatabaseManager(directory: dir)
        let store = ItemStore(writer: dbm.writer, blobs: BlobStore(directory: dbm.blobsDirectory))
        _ = try store.save(makeBlobItem(0x01, hashSeed: "a"))
        _ = try store.save(makeBlobItem(0x02, hashSeed: "b"))
        try store.clearHistory(keepFavorites: true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dbm.blobsDirectory.path).count, 0)
        XCTAssertEqual(try store.recentItems(limit: 10).count, 0)
    }

    func testSharedBlobSurvivesPartialDelete() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopyTests-\(UUID().uuidString)")
        let dbm = try DatabaseManager(directory: dir)
        let store = ItemStore(writer: dbm.writer, blobs: BlobStore(directory: dbm.blobsDirectory))
        // Same rep data (same blob key), different content hashes.
        let a = try store.save(makeBlobItem(0x03, hashSeed: "x"))
        _ = try store.save(makeBlobItem(0x03, hashSeed: "y"))
        try store.delete(itemID: a.id!)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dbm.blobsDirectory.path).count, 1,
                       "blob still referenced by the second item must survive")
    }

    func testClearHistoryIncludingFavorites() throws {
        let store = try makeTempStore()
        let fav = try store.save(makeText("fav"))
        try store.setFavorite(itemID: fav.id!, true)
        try store.clearHistory(keepFavorites: false)
        XCTAssertEqual(try store.recentItems(limit: 10).count, 0)
    }

    func testSearchStillFindsItemAfterTouch() throws {
        let store = try makeTempStore()
        let item = try store.save(makeText("touchable content"))
        try store.touch(itemID: item.id!)
        XCTAssertEqual(try store.search("touchable").count, 1)
    }

    func testPlainTextOnlyWithNoPlainRepWritesAllReps() {
        // Documented behavior: without a plain-text rep, place() writes all reps unchanged.
        let pasteboard = SpyPasteboard()
        let service = PasteService(pasteboard: pasteboard, keyPoster: SpyKeyPoster())
        let reps = [CapturedRepresentation(uti: "public.png", data: Data([0x01]))]
        service.place(reps, plainTextOnly: true)
        XCTAssertEqual(pasteboard.written[0].representations, reps)
    }

    func testMenuTitle() throws {
        var item = try makeTempStore().save(makeText("  line one\nline two  "))
        XCTAssertEqual(item.menuTitle, "line one line two")
        item.kind = .image
        XCTAssertEqual(item.menuTitle, "Image")
        item.kind = .file
        item.plainText = "a.txt\nb.txt"
        XCTAssertEqual(item.menuTitle, "a.txt")
        item.kind = .text
        item.plainText = String(repeating: "x", count: 60)
        XCTAssertEqual(item.menuTitle, String(repeating: "x", count: 50) + "…")
    }
}
