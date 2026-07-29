import Foundation
import GRDB

public final class DatabaseManager {
    public let writer: any DatabaseWriter
    public let blobsDirectory: URL

    public static func makeDefault() throws -> DatabaseManager {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Copy", isDirectory: true)
        return try DatabaseManager(directory: appSupport)
    }

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        blobsDirectory = directory.appendingPathComponent("blobs", isDirectory: true)
        try FileManager.default.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)
        writer = try DatabasePool(path: directory.appendingPathComponent("copy.sqlite").path)
        try Self.migrator.migrate(writer)
    }

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "item") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("uuid", .text).notNull().unique()
                t.column("kind", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("lastUsedAt", .datetime).notNull().indexed()
                t.column("plainText", .text)
                t.column("linkTitle", .text)
                t.column("appBundleID", .text)
                t.column("appName", .text)
                t.column("contentHash", .text).notNull().unique()
                t.column("sizeBytes", .integer).notNull().defaults(to: 0)
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "representation") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("item", onDelete: .cascade).notNull()
                t.column("uti", .text).notNull()
                t.column("inlineData", .blob)
                t.column("blobKey", .text)
            }
            try db.create(table: "pinboard") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("symbol", .text).notNull()
                t.column("tint", .text).notNull()
                t.column("sortIndex", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "pinboard_item") { t in
                t.belongsTo("pinboard", onDelete: .cascade).notNull()
                t.belongsTo("item", onDelete: .cascade).notNull()
                t.column("sortIndex", .integer).notNull().defaults(to: 0)
                t.primaryKey(["pinboardId", "itemId"])
            }
            try db.create(virtualTable: "item_fts", using: FTS5()) { t in
                t.synchronize(withTable: "item")
                t.tokenizer = .unicode61()
                t.column("plainText")
                t.column("appName")
                t.column("linkTitle")
            }
        }
        return migrator
    }
}
