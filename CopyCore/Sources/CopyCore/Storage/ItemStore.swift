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
                try existing.update(db)
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
            for rep in captured.representations {
                var record: Representation
                if rep.data.count > Self.inlineThreshold {
                    let key = try blobs.store(rep.data)
                    record = Representation(id: nil, itemId: item.id!, uti: rep.uti,
                                            inlineData: nil, blobKey: key)
                } else {
                    record = Representation(id: nil, itemId: item.id!, uti: rep.uti,
                                            inlineData: rep.data, blobKey: nil)
                }
                try record.insert(db)
            }
            return item
        }
    }

    public func recentItems(limit: Int = 50) throws -> [ClipItem] {
        try writer.read { db in
            try ClipItem.order(Column("lastUsedAt").desc).limit(limit).fetchAll(db)
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
}
