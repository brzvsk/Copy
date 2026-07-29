import XCTest
import GRDB
@testable import CopyCore

final class PinboardColorEmojiTests: XCTestCase {
    func testV3MigrationAddsEmojiColumnAndPreservesExistingPinboards() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let writer = try DatabasePool(path: dir.appendingPathComponent("copy.sqlite").path)

        // Simulate an existing user on the v2 schema (no emoji column yet).
        try DatabaseManager.migrator.migrate(writer, upTo: "v2")
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO pinboard (name, symbol, tint, sortIndex)
                VALUES (?, ?, ?, ?)
                """, arguments: ["Old Board", "pin", "", 1])
        }

        // Now bring it fully up to date; only v3 should run.
        try DatabaseManager.migrator.migrate(writer)

        let columns = try writer.read { db in try db.columns(in: "pinboard") }
        XCTAssertTrue(columns.contains { $0.name == "emoji" })

        let pinboards = PinboardStore(writer: writer)
        let all = try pinboards.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].name, "Old Board")
        XCTAssertEqual(all[0].symbol, "pin")
        XCTAssertNil(all[0].emoji)
    }

    func testCreateWithEmojiAndTintRoundTrips() throws {
        let (_, pinboards) = try makeTempStores()
        let board = try pinboards.create(name: "Design", symbol: "paintbrush", emoji: "🎨", tint: "007AFF")
        XCTAssertEqual(board.emoji, "🎨")
        XCTAssertEqual(board.tint, "007AFF")

        let reloaded = try pinboards.all()
        XCTAssertEqual(reloaded[0].emoji, "🎨")
        XCTAssertEqual(reloaded[0].tint, "007AFF")
    }

    func testCreateWithoutEmojiOrTintKeepsOldDefaults() throws {
        let (_, pinboards) = try makeTempStores()
        let board = try pinboards.create(name: "Work", symbol: "briefcase")
        XCTAssertNil(board.emoji)
        XCTAssertEqual(board.tint, "")
    }

    func testSetEmojiAndSetTintUpdateAndClearExistingPinboard() throws {
        let (_, pinboards) = try makeTempStores()
        let board = try pinboards.create(name: "Snippets", symbol: "folder")

        try pinboards.setEmoji(id: board.id!, "📌")
        try pinboards.setTint(id: board.id!, "FF3B30")

        let tinted = try pinboards.all()
        XCTAssertEqual(tinted[0].emoji, "📌")
        XCTAssertEqual(tinted[0].tint, "FF3B30")

        try pinboards.setEmoji(id: board.id!, nil)
        try pinboards.setTint(id: board.id!, "")

        let cleared = try pinboards.all()
        XCTAssertNil(cleared[0].emoji)
        XCTAssertEqual(cleared[0].tint, "")
    }
}
