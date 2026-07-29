import XCTest
import GRDB
@testable import CopyCore

final class RenameAndCreateTests: XCTestCase {
    func testV2MigrationAddsColumnsAndPreservesExistingV1Data() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let writer = try DatabasePool(path: dir.appendingPathComponent("copy.sqlite").path)

        // Simulate an existing user on the v1 schema (no title/recognizedText yet).
        try DatabaseManager.migrator.migrate(writer, upTo: "v1")
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO item (uuid, kind, createdAt, lastUsedAt, plainText, contentHash, sizeBytes, isFavorite)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: ["v1-uuid", "text", Date(timeIntervalSince1970: 1000),
                                 Date(timeIntervalSince1970: 1000), "old row", "hash-old", 7, false])
        }

        // Now bring it fully up to date; only v2 should run.
        try DatabaseManager.migrator.migrate(writer)

        let columns = try writer.read { db in try db.columns(in: "item") }
        XCTAssertTrue(columns.contains { $0.name == "title" })
        XCTAssertTrue(columns.contains { $0.name == "recognizedText" })

        let oldRow = try writer.read { db in
            try ClipItem.filter(Column("uuid") == "v1-uuid").fetchOne(db)
        }
        XCTAssertEqual(oldRow?.plainText, "old row")
        XCTAssertNil(oldRow?.title)
        XCTAssertNil(oldRow?.recognizedText)

        // Existing save/fetch behavior must still work post-migration.
        let store = ItemStore(writer: writer, blobs: BlobStore(directory: dir.appendingPathComponent("blobs")))
        let saved = try store.save(makeText("fresh after migration"))
        XCTAssertEqual(try store.recentItems(limit: 10).count, 2)
        XCTAssertEqual(saved.plainText, "fresh after migration")
    }

    func testSetTitleThenSearchByTitleFindsItem() throws {
        let store = try makeTempStore()
        let saved = try store.save(makeText("unrelated body text"))

        try store.setTitle(itemID: saved.id!, "Wombat Recipe")
        let hits = try store.search("Wombat")
        XCTAssertEqual(hits.map(\.id), [saved.id])
        XCTAssertEqual(hits.first?.title, "Wombat Recipe")

        try store.setTitle(itemID: saved.id!, nil)
        XCTAssertNil(try store.recentItems(limit: 10).first?.title)
        XCTAssertEqual(try store.search("Wombat").count, 0)
    }

    func testCreateTextItemPersistsIsSearchableAndUsesCopyAsSource() throws {
        let store = try makeTempStore()
        let created = try store.createTextItem("Grocery list: eggs, milk", title: "Groceries")

        XCTAssertNotNil(created.id)
        XCTAssertEqual(created.kind, .text)
        XCTAssertEqual(created.plainText, "Grocery list: eggs, milk")
        XCTAssertEqual(created.title, "Groceries")
        XCTAssertEqual(created.appName, "Copy")
        XCTAssertEqual(created.appBundleID, "com.tarikbc.Copy")

        let reps = try store.representations(forItemID: created.id!)
        XCTAssertEqual(reps.map(\.uti), ["public.utf8-plain-text"])
        XCTAssertEqual(String(decoding: reps[0].data, as: UTF8.self), "Grocery list: eggs, milk")

        XCTAssertEqual(try store.search("Grocery").map(\.id), [created.id])
        XCTAssertEqual(try store.search("Groceries").map(\.id), [created.id])
    }

    func testCreateTextItemDedupsByContentHashAndBumpsLastUsed() throws {
        let store = try makeTempStore()
        let first = try store.createTextItem("dup body", title: "Original", now: Date(timeIntervalSince1970: 1000))
        let again = try store.createTextItem("dup body", title: "Ignored", now: Date(timeIntervalSince1970: 2000))

        XCTAssertEqual(first.id, again.id)
        XCTAssertEqual(again.title, "Original", "dedup path should not overwrite an existing title")
        XCTAssertEqual(again.lastUsedAt, Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(try store.recentItems(limit: 10).count, 1)
        XCTAssertEqual(try store.representations(forItemID: first.id!).count, 1)
    }

    func testDisplayTitlePrefersTitleOverMenuTitleAndFallsBackWhenEmpty() {
        var item = ClipItem(
            id: 1, uuid: "u", kind: .text, createdAt: Date(), lastUsedAt: Date(),
            plainText: "hello world", linkTitle: nil, appBundleID: nil, appName: nil,
            contentHash: "h", sizeBytes: 5, isFavorite: false)

        XCTAssertEqual(item.displayTitle, item.menuTitle)

        item.title = "Custom Title"
        XCTAssertEqual(item.displayTitle, "Custom Title")

        item.title = ""
        XCTAssertEqual(item.displayTitle, item.menuTitle, "an empty title must fall back to menuTitle")
    }

    func testRecognizedTextColumnIsIndexedByFTS() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopyTests-\(UUID().uuidString)")
        let dbm = try DatabaseManager(directory: dir)
        let store = ItemStore(writer: dbm.writer, blobs: BlobStore(directory: dbm.blobsDirectory))
        let saved = try store.save(makeText("a screenshot"))

        // Simulate what Task 2's setRecognizedText will do, to prove the v2 FTS
        // rebuild already indexes this column.
        try dbm.writer.write { db in
            try db.execute(
                sql: "UPDATE item SET recognizedText = ? WHERE id = ?",
                arguments: ["invoice total amount due", saved.id!])
        }

        XCTAssertEqual(try store.search("invoice").map(\.id), [saved.id])
    }
}
