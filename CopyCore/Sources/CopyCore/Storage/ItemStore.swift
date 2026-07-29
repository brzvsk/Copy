import Foundation
import GRDB

public struct ItemStore {
    public static let inlineThreshold = 65_536
    public static let deleteChunkSize = 500
    public static let userCreatedAppName = "Copy"
    public static let userCreatedAppBundleID = "com.tarikbc.Copy"

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

                // Exclude the favicon representation from both the old-blob-key lookup
                // and the wipe below: a favicon is set out-of-band (`setFavicon`) after
                // the item is first saved, so re-copying the same content and hitting
                // this dedup branch must not erase it.
                let oldKeys = try String.fetchAll(db, sql:
                    "SELECT DISTINCT blobKey FROM representation WHERE itemId = ? AND blobKey IS NOT NULL AND uti != ?",
                    arguments: [existing.id!, CopyPasteboard.faviconUTI])
                try Representation.filter(
                    Column("itemId") == existing.id! && Column("uti") != CopyPasteboard.faviconUTI
                ).deleteAll(db)
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

    /// Looks up a single item by its stable uuid, regardless of how far back it sits
    /// in `lastUsedAt` order — unlike `recentItems`, this isn't bounded by a `limit`,
    /// so it's the right tool for resolving a uuid held elsewhere (e.g. a Paste Stack
    /// queue entry) that may have aged out of any "recent" window.
    public func item(uuid: String) throws -> ClipItem? {
        try writer.read { db in
            try ClipItem.filter(Column("uuid") == uuid).fetchOne(db)
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

        var allKeys: [String] = []
        for chunk in chunked(ids, into: Self.deleteChunkSize) {
            let placeholders = chunk.map { _ in "?" }.joined(separator: ",")
            let keys = try String.fetchAll(db, sql: """
                SELECT DISTINCT blobKey FROM representation
                WHERE itemId IN (\(placeholders)) AND blobKey IS NOT NULL
                """, arguments: StatementArguments(chunk))
            allKeys.append(contentsOf: keys)
        }

        for chunk in chunked(ids, into: Self.deleteChunkSize) {
            try ClipItem.filter(chunk.contains(Column("id"))).deleteAll(db)
        }

        try cleanOrphanBlobs(allKeys, in: db)
    }

    private func chunked<T>(_ array: [T], into size: Int) -> [[T]] {
        stride(from: 0, to: array.count, by: size).map {
            Array(array[$0..<Swift.min($0 + size, array.count)])
        }
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
            item.linkTitle = nil
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

    @discardableResult
    public func prune(olderThan cutoff: Date?, maxItems: Int?) throws -> Int {
        guard cutoff != nil || maxItems != nil else { return 0 }

        return try writer.write { db in
            var doomed: Set<Int64> = []

            if let cutoff {
                let oldIds = try Int64.fetchAll(db, sql: """
                    SELECT id FROM item
                    WHERE lastUsedAt < ? AND isFavorite = false
                    AND id NOT IN (SELECT DISTINCT itemId FROM pinboard_item)
                    """, arguments: [cutoff])
                doomed.formUnion(oldIds)
            }

            if let maxItems {
                let newestIds = try Int64.fetchAll(db, sql: """
                    SELECT id FROM item
                    WHERE isFavorite = false
                    AND id NOT IN (SELECT DISTINCT itemId FROM pinboard_item)
                    ORDER BY lastUsedAt DESC
                    LIMIT ?
                    """, arguments: [maxItems])
                let newestSet = Set(newestIds)

                let excessIds = try Int64.fetchAll(db, sql: """
                    SELECT id FROM item
                    WHERE isFavorite = false
                    AND id NOT IN (SELECT DISTINCT itemId FROM pinboard_item)
                    """)
                for id in excessIds {
                    if !newestSet.contains(id) {
                        doomed.insert(id)
                    }
                }
            }

            guard !doomed.isEmpty else { return 0 }

            let doomedArray = Array(doomed)
            try deleteItems(ClipItem.filter(doomedArray.contains(Column("id"))), in: db)
            return doomedArray.count
        }
    }

    public func setLinkTitle(itemID: Int64, _ title: String?) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE item SET linkTitle = ? WHERE id = ?",
                arguments: [title, itemID])
        }
    }

    /// Sets the user-assigned label shown in place of the auto-generated title.
    /// Passing `nil` (or an empty string) clears it, reverting display to the auto title.
    public func setTitle(itemID: Int64, _ title: String?) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE item SET title = ? WHERE id = ?",
                arguments: [title, itemID])
        }
    }

    /// Inserts a user-created plain-text item (e.g. from ⌘N), deduping by content hash
    /// like `save`: if an identical-hash item already exists, its `lastUsedAt` is bumped
    /// and it is returned unchanged (the existing title is left as-is).
    @discardableResult
    public func createTextItem(_ text: String, title: String? = nil, now: Date = Date()) throws -> ClipItem {
        let hash = BlobStore.key(for: Data(text.utf8))
        return try writer.write { db in
            if var existing = try ClipItem.filter(Column("contentHash") == hash).fetchOne(db) {
                existing.lastUsedAt = now
                try existing.update(db)
                return existing
            }
            var item = ClipItem(
                id: nil, uuid: UUID().uuidString, kind: ItemKind.forText(text),
                createdAt: now, lastUsedAt: now,
                plainText: text, linkTitle: nil,
                appBundleID: Self.userCreatedAppBundleID, appName: Self.userCreatedAppName,
                contentHash: hash,
                sizeBytes: text.utf8.count,
                isFavorite: false,
                title: title
            )
            try item.insert(db)
            try insertRepresentations(
                [CapturedRepresentation(uti: "public.utf8-plain-text", data: Data(text.utf8))],
                itemID: item.id!, in: db)
            return item
        }
    }

    public func setFavicon(itemID: Int64, pngData: Data) throws {
        try writer.write { db in
            // Capture old favicon blobKey before deletion
            let oldKeys = try String.fetchAll(db, sql: """
                SELECT DISTINCT blobKey FROM representation
                WHERE itemId = ? AND uti = ? AND blobKey IS NOT NULL
                """, arguments: [itemID, CopyPasteboard.faviconUTI])

            // Delete any existing favicon representation for this item
            try Representation.filter(
                Column("itemId") == itemID && Column("uti") == CopyPasteboard.faviconUTI
            ).deleteAll(db)

            // Insert the new favicon representation via insertRepresentations
            try insertRepresentations(
                [CapturedRepresentation(uti: CopyPasteboard.faviconUTI, data: pngData)],
                itemID: itemID, in: db)

            // Clean up any orphaned blobs
            try cleanOrphanBlobs(oldKeys, in: db)
        }
    }

    public func favicon(forItemID id: Int64) throws -> Data? {
        let record = try writer.read { db in
            try Representation.filter(
                Column("itemId") == id && Column("uti") == CopyPasteboard.faviconUTI
            ).fetchOne(db)
        }

        if let record {
            if let inlineData = record.inlineData {
                return inlineData
            }
            if let key = record.blobKey {
                return blobs.data(forKey: key)
            }
        }

        return nil
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
