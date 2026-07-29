import Foundation
import GRDB

public struct ItemStore {
    public static let inlineThreshold = 65_536

    private let writer: any DatabaseWriter
    private let blobs: BlobStore

    public init(writer: any DatabaseWriter, blobs: BlobStore) {
        self.writer = writer
        self.blobs = blobs
    }

    @discardableResult
    public func save(_ captured: CapturedItem, now: Date = Date()) throws -> ClipItem {
        let hash = BlobStore.key(for: captured.hashData)
        return try writer.write { db in
            if var existing = try ClipItem.filter(Column("contentHash") == hash).fetchOne(db) {
                existing.lastUsedAt = now
                existing.appBundleID = captured.sourceBundleID
                existing.appName = captured.sourceAppName
                existing.sizeBytes = captured.representations.reduce(0) { $0 + $1.data.count }
                existing.kind = captured.kind
                try existing.update(db)

                let oldKeys = try String.fetchAll(db, sql:
                    "SELECT DISTINCT blobKey FROM representation WHERE itemId = ? AND blobKey IS NOT NULL",
                    arguments: [existing.id!])
                try Representation.filter(Column("itemId") == existing.id!).deleteAll(db)
                try insertRepresentations(captured.representations, itemID: existing.id!, in: db)
                try cleanOrphanBlobs(oldKeys, in: db)
                return existing
            }
            var item = ClipItem(
                id: nil, uuid: UUID().uuidString, kind: captured.kind,
                createdAt: now, lastUsedAt: now,
                plainText: captured.plainText, linkTitle: nil,
                appBundleID: captured.sourceBundleID, appName: captured.sourceAppName,
                contentHash: hash,
                sizeBytes: captured.representations.reduce(0) { $0 + $1.data.count },
                isFavorite: false
            )
            try item.insert(db)
            try insertRepresentations(captured.representations, itemID: item.id!, in: db)
            return item
        }
    }

    private func insertRepresentations(_ reps: [CapturedRepresentation], itemID: Int64, in db: Database) throws {
        for rep in reps {
            var record: Representation
            if rep.data.count > Self.inlineThreshold {
                let key = try blobs.store(rep.data)
                record = Representation(id: nil, itemId: itemID, uti: rep.uti, inlineData: nil, blobKey: key)
            } else {
                record = Representation(id: nil, itemId: itemID, uti: rep.uti, inlineData: rep.data, blobKey: nil)
            }
            try record.insert(db)
        }
    }

    private func cleanOrphanBlobs(_ keys: [String], in db: Database) throws {
        for key in keys {
            let stillUsed = try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM representation WHERE blobKey = ?", arguments: [key]) ?? 0
            if stillUsed == 0 { blobs.delete(key: key) }
        }
    }

    public func recentItems(kinds: Set<ItemKind>? = nil, limit: Int = 50) throws -> [ClipItem] {
        try writer.read { db in
            var request = ClipItem.order(Column("lastUsedAt").desc).limit(limit)
            if let kinds {
                request = request.filter(kinds.map(\.rawValue).contains(Column("kind")))
            }
            return try request.fetchAll(db)
        }
    }

    public func representations(forItemID id: Int64) throws -> [CapturedRepresentation] {
        let records = try writer.read { db in
            try Representation.filter(Column("itemId") == id).fetchAll(db)
        }
        return records.compactMap { rep in
            if let data = rep.inlineData {
                return CapturedRepresentation(uti: rep.uti, data: data)
            }
            if let key = rep.blobKey, let data = blobs.data(forKey: key) {
                return CapturedRepresentation(uti: rep.uti, data: data)
            }
            return nil
        }
    }

    public func search(_ query: String, kinds: Set<ItemKind>? = nil, limit: Int = 50) throws -> [ClipItem] {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else { return [] }
        var sql = """
            SELECT item.* FROM item
            JOIN item_fts ON item_fts.rowid = item.id
            WHERE item_fts MATCH ?
            """
        var arguments: [any DatabaseValueConvertible] = [pattern]
        if let kinds {
            let names = kinds.map(\.rawValue).sorted()
            sql += " AND item.kind IN (\(names.map { _ in "?" }.joined(separator: ",")))"
            arguments.append(contentsOf: names)
        }
        sql += " ORDER BY item.lastUsedAt DESC LIMIT ?"
        arguments.append(limit)
        return try writer.read { db in
            try ClipItem.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }
    }

    public func touch(itemID: Int64, now: Date = Date()) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE item SET lastUsedAt = ? WHERE id = ?",
                arguments: [now, itemID])
        }
    }

    public func setFavorite(itemID: Int64, _ favorite: Bool) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE item SET isFavorite = ? WHERE id = ?",
                arguments: [favorite, itemID])
        }
    }

    public func delete(itemID: Int64) throws {
        try writer.write { db in
            try deleteItems(ClipItem.filter(Column("id") == itemID), in: db)
        }
    }

    public func clearHistory(keepFavorites: Bool = true) throws {
        try writer.write { db in
            let memberIDs = "SELECT DISTINCT itemId FROM pinboard_item"
            var doomed = ClipItem.filter(sql: "id NOT IN (\(memberIDs))")
            if keepFavorites {
                doomed = doomed.filter(Column("isFavorite") == false)
            }
            try deleteItems(doomed, in: db)
        }
    }

    /// Deletes matching items and any blobs no longer referenced afterwards.
    private func deleteItems(_ request: QueryInterfaceRequest<ClipItem>, in db: Database) throws {
        let ids = try request.selectPrimaryKey(as: Int64.self).fetchAll(db)
        guard !ids.isEmpty else { return }
        let keys = try String.fetchAll(db, sql: """
            SELECT DISTINCT blobKey FROM representation
            WHERE itemId IN (\(ids.map { String($0) }.joined(separator: ","))) AND blobKey IS NOT NULL
            """)
        try request.deleteAll(db)
        try cleanOrphanBlobs(keys, in: db)
    }

    public func observeRecent(kinds: Set<ItemKind>? = nil, limit: Int = 100,
                              onError: @escaping (Error) -> Void,
                              onChange: @escaping ([ClipItem]) -> Void) -> ObservationToken {
        let observation = ValueObservation.tracking { db -> [ClipItem] in
            var request = ClipItem.order(Column("lastUsedAt").desc).limit(limit)
            if let kinds {
                request = request.filter(kinds.map(\.rawValue).contains(Column("kind")))
            }
            return try request.fetchAll(db)
        }
        let cancellable = observation.start(in: writer,
                                            scheduling: .async(onQueue: .main),
                                            onError: onError,
                                            onChange: onChange)
        return ObservationToken(cancellable)
    }

    @discardableResult
    public func replaceContent(itemID: Int64, with text: String, now: Date = Date()) throws -> ClipItem {
        let hash = BlobStore.key(for: Data(text.utf8))
        return try writer.write { db in
            guard var item = try ClipItem.fetchOne(db, key: itemID) else {
                throw DatabaseError(message: "item not found")
            }
            if var winner = try ClipItem
                .filter(Column("contentHash") == hash && Column("id") != itemID)
                .fetchOne(db) {
                winner.lastUsedAt = now
                try winner.update(db)
                try deleteItems(ClipItem.filter(Column("id") == itemID), in: db)
                return winner
            }
            let oldKeys = try String.fetchAll(db, sql:
                "SELECT DISTINCT blobKey FROM representation WHERE itemId = ? AND blobKey IS NOT NULL",
                arguments: [itemID])
            try Representation.filter(Column("itemId") == itemID).deleteAll(db)
            item.kind = ItemKind.forText(text)
            item.plainText = text
            item.contentHash = hash
            item.sizeBytes = text.utf8.count
            item.lastUsedAt = now
            try item.update(db)
            try insertRepresentations(
                [CapturedRepresentation(uti: "public.utf8-plain-text", data: Data(text.utf8))],
                itemID: itemID, in: db)
            try cleanOrphanBlobs(oldKeys, in: db)
            return item
        }
    }
}

public final class ObservationToken {
    private let cancellable: AnyDatabaseCancellable

    init(_ cancellable: AnyDatabaseCancellable) {
        self.cancellable = cancellable
    }

    public func cancel() {
        cancellable.cancel()
    }

    deinit {
        cancellable.cancel()
    }
}
