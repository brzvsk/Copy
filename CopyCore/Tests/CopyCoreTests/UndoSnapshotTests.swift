import XCTest
@testable import CopyCore

final class UndoSnapshotTests: XCTestCase {
    func testArchivedSnapshotRoundTripsThroughDeleteAndRestore() throws {
        let store = try makeTempStore()
        let saved = try store.save(makeText("undo me please"))
        let id = saved.id!
        let hash = saved.contentHash

        // Capture, then delete.
        let snapshot = try store.archivedSnapshot(itemID: id)
        try store.delete(itemID: id)
        XCTAssertNil(try store.item(contentHash: hash), "item should be gone after delete")

        // Restore via the same path the app's undo uses.
        let inserted = try store.importArchived(snapshot)
        XCTAssertTrue(inserted, "snapshot should re-insert a fresh item")

        let restored = try store.item(contentHash: hash)
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.plainText, "undo me please")
        XCTAssertEqual(restored?.kind, saved.kind)
        // Representations survive the round trip.
        let reps = try store.representations(forItemID: restored!.id!)
        XCTAssertEqual(reps.map { String(decoding: $0.data, as: UTF8.self) }, ["undo me please"])
        // And it is searchable again (FTS reindexed on re-insert).
        XCTAssertEqual(try store.search("undo").map(\.plainText), ["undo me please"])
    }

    func testArchivedSnapshotPreservesTitle() throws {
        let store = try makeTempStore()
        let saved = try store.createTextItem("body text", title: "My Title")

        let snapshot = try store.archivedSnapshot(itemID: saved.id!)
        try store.delete(itemID: saved.id!)
        _ = try store.importArchived(snapshot)

        let restored = try store.item(contentHash: saved.contentHash)
        XCTAssertEqual(restored?.title, "My Title")
    }
}
