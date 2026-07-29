import Foundation

/// A single representation inside an exported item, with its bytes base64-encoded so
/// the whole archive round-trips through plain JSON.
public struct ArchivedRep: Codable, Equatable {
    public let uti: String
    public let dataBase64: String
}

/// A clipboard item as it appears inside a `ClipArchive`. Carries everything needed to
/// reconstruct the item faithfully (timestamps, title, favorite flag, recognized OCR
/// text, and every representation), keyed for dedup by `contentHash` — the same hash
/// `ItemStore` already uses to recognize identical content.
public struct ArchivedItem: Codable, Equatable {
    public let kind: String
    public let plainText: String?
    public let title: String?
    public let linkTitle: String?
    public let recognizedText: String?
    public let appName: String?
    public let appBundleID: String?
    public let createdAt: Date
    public let lastUsedAt: Date
    public let contentHash: String
    public let isFavorite: Bool
    public let representations: [ArchivedRep]
}

/// A pinboard as it appears inside a `ClipArchive`. Membership is stored as the
/// `contentHash` of each member item rather than a database id, since ids are not
/// stable across a export/import round trip — `ArchiveIO.importArchive` resolves
/// each hash back to a (possibly newly-inserted) item id in the target store.
public struct ArchivedPinboard: Codable, Equatable {
    public let name: String
    public let symbol: String
    public let emoji: String?
    public let tint: String
    public let itemHashes: [String]
}

/// The top-level, versioned envelope written to and read from a `.json` backup file.
public struct ClipArchive: Codable, Equatable {
    public let version: Int
    public let exportedAt: Date
    public let items: [ArchivedItem]
    public let pinboards: [ArchivedPinboard]
}

public enum ArchiveError: Error, LocalizedError {
    case unknownItemKind(String)
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unknownItemKind(let kind):
            return "The archive contains an item of unknown kind \"\(kind)\"."
        case .unsupportedVersion(let version):
            return "This archive (version \(version)) was made by a newer version of Copy."
        }
    }
}

/// Serializes and restores the full clipboard history and pinboards to/from a single
/// JSON archive, for the status menu's "Export…"/"Import…" actions. Import dedups by
/// content hash (the same identity `ItemStore.save` already uses), so importing the
/// same archive twice never creates duplicates.
public enum ArchiveIO {
    public static let currentVersion = 1

    public static func export(items: ItemStore, pinboards: PinboardStore, now: Date = Date()) throws -> Data {
        let recent = try items.recentItems(limit: 100_000)
        let archivedItems: [ArchivedItem] = try recent.map { item in
            let reps = try items.representations(forItemID: item.id!)
            return ArchivedItem(
                kind: item.kind.rawValue,
                plainText: item.plainText,
                title: item.title,
                linkTitle: item.linkTitle,
                recognizedText: item.recognizedText,
                appName: item.appName,
                appBundleID: item.appBundleID,
                createdAt: item.createdAt,
                lastUsedAt: item.lastUsedAt,
                contentHash: item.contentHash,
                isFavorite: item.isFavorite,
                representations: reps.map { ArchivedRep(uti: $0.uti, dataBase64: $0.data.base64EncodedString()) }
            )
        }

        let boards = try pinboards.all()
        let archivedBoards: [ArchivedPinboard] = try boards.map { board in
            let members = try pinboards.items(in: board.id!, limit: 100_000)
            return ArchivedPinboard(
                name: board.name, symbol: board.symbol, emoji: board.emoji, tint: board.tint,
                itemHashes: members.map(\.contentHash)
            )
        }

        let archive = ClipArchive(version: currentVersion, exportedAt: now,
                                  items: archivedItems, pinboards: archivedBoards)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    @discardableResult
    public static func importArchive(_ data: Data, into items: ItemStore, pinboards: PinboardStore) throws
        -> (itemsAdded: Int, itemsSkipped: Int, pinboardsAdded: Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(ClipArchive.self, from: data)
        guard archive.version <= currentVersion else {
            throw ArchiveError.unsupportedVersion(archive.version)
        }

        var itemsAdded = 0
        var itemsSkipped = 0
        for archivedItem in archive.items {
            do {
                if try items.importArchived(archivedItem) {
                    itemsAdded += 1
                }
            } catch ArchiveError.unknownItemKind {
                // An archive from a newer Copy version may carry an item kind this
                // build doesn't know about — skip just that item rather than failing
                // the whole import.
                itemsSkipped += 1
            }
        }

        var pinboardsAdded = 0
        // Pinboard names have no uniqueness constraint (a user can have two boards
        // named "Work"), so this dedup dictionary must tolerate duplicate keys —
        // `uniquingKeysWith` keeps the first match and merges archived membership
        // into it rather than trapping.
        var boardsByName = Dictionary(try pinboards.all().map { ($0.name, $0) },
                                      uniquingKeysWith: { first, _ in first })
        for archivedBoard in archive.pinboards {
            let board: Pinboard
            if let existing = boardsByName[archivedBoard.name] {
                board = existing
            } else {
                board = try pinboards.create(name: archivedBoard.name, symbol: archivedBoard.symbol,
                                             emoji: archivedBoard.emoji, tint: archivedBoard.tint)
                boardsByName[archivedBoard.name] = board
                pinboardsAdded += 1
            }
            guard let boardID = board.id else { continue }
            for hash in archivedBoard.itemHashes {
                if let member = try items.item(contentHash: hash), let memberID = member.id {
                    try pinboards.add(itemID: memberID, to: boardID)
                }
            }
        }

        return (itemsAdded, itemsSkipped, pinboardsAdded)
    }
}
