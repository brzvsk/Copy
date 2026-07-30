import XCTest
@testable import CopyCore

func makeTempStore() throws -> ItemStore {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("CopyTests-\(UUID().uuidString)")
    let dbm = try DatabaseManager(directory: dir)
    return ItemStore(writer: dbm.writer, blobs: BlobStore(directory: dbm.blobsDirectory))
}

func makeText(_ s: String) -> CapturedItem {
    CapturedItem(
        kind: .text, plainText: s, hashData: Data(s.utf8),
        representations: [CapturedRepresentation(uti: "public.utf8-plain-text", data: Data(s.utf8))],
        sourceBundleID: "com.test.app", sourceAppName: "TestApp"
    )
}

/// An image `CapturedItem` of a given stored byte size and a distinct hash (so successive
/// calls don't dedup into one item).
func makeImage(bytes: Int, tag: String) -> CapturedItem {
    let data = Data(repeating: 0xAB, count: bytes)
    return CapturedItem(
        kind: .image, plainText: "Image", hashData: Data(tag.utf8),
        representations: [CapturedRepresentation(uti: "public.png", data: data)],
        sourceBundleID: "com.test.app", sourceAppName: "TestApp"
    )
}

final class ItemStoreTests: XCTestCase {
    func testSaveAndFetchRecent() throws {
        let store = try makeTempStore()
        let saved = try store.save(makeText("hello"))
        XCTAssertNotNil(saved.id)
        XCTAssertEqual(saved.kind, .text)
        XCTAssertEqual(saved.appBundleID, "com.test.app")

        let recent = try store.recentItems(limit: 10)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent[0].plainText, "hello")
    }

    func testStorageBreakdownGroupsByKindAndSumsBytes() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("aa"))          // text, 2 bytes
        _ = try store.save(makeText("bbbb"))        // text, 4 bytes
        _ = try store.save(makeImage(bytes: 100, tag: "img1"))

        let byKind = Dictionary(uniqueKeysWithValues: try store.storageBreakdown().map { ($0.kind, $0) })
        XCTAssertEqual(byKind[.text]?.count, 2)
        XCTAssertEqual(byKind[.text]?.bytes, 6)
        XCTAssertEqual(byKind[.image]?.count, 1)
        XCTAssertEqual(byKind[.image]?.bytes, 100)
        XCTAssertNil(byKind[.link])                 // kinds with no items are omitted
    }

    func testStorageBreakdownExcludesFavorites() throws {
        let store = try makeTempStore()
        let fav = try store.save(makeText("keep"))
        try store.setFavorite(itemID: fav.id!, true)
        _ = try store.save(makeText("drop"))

        let text = try store.storageBreakdown().first { $0.kind == .text }
        XCTAssertEqual(text?.count, 1)              // favorite excluded from the clearable set
        XCTAssertEqual(text?.bytes, 4)              // only "drop"
    }

    func testClearHistoryByKindClearsOnlyThatKind() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("t1"))
        _ = try store.save(makeImage(bytes: 10, tag: "img1"))
        _ = try store.save(makeImage(bytes: 20, tag: "img2"))

        try store.clearHistory(kind: .image)

        XCTAssertEqual(try store.recentItems(limit: 10).map(\.kind), [.text])
        XCTAssertNil(try store.storageBreakdown().first { $0.kind == .image })
    }

    func testClearHistoryByKindKeepsFavorites() throws {
        let store = try makeTempStore()
        let fav = try store.save(makeImage(bytes: 30, tag: "favimg"))
        try store.setFavorite(itemID: fav.id!, true)
        _ = try store.save(makeImage(bytes: 10, tag: "img1"))

        try store.clearHistory(kind: .image)

        XCTAssertEqual(try store.recentItems(limit: 10).count, 1)  // favorite image survives
    }

    func testRecentOrderedByLastUsedDescending() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("first"), now: Date(timeIntervalSince1970: 1000))
        _ = try store.save(makeText("second"), now: Date(timeIntervalSince1970: 2000))
        let recent = try store.recentItems(limit: 10)
        XCTAssertEqual(recent.map(\.plainText), ["second", "first"])
    }

    func testItemByUUIDRoundTripsAndNilsOnUnknown() throws {
        let store = try makeTempStore()
        let saved = try store.save(makeText("find me"))

        let found = try store.item(uuid: saved.uuid)
        XCTAssertEqual(found?.id, saved.id)
        XCTAssertEqual(found?.plainText, "find me")

        XCTAssertNil(try store.item(uuid: "not-a-real-uuid"))
    }

    func testRepresentationsRoundTrip() throws {
        let store = try makeTempStore()
        let saved = try store.save(makeText("round trip"))
        let reps = try store.representations(forItemID: saved.id!)
        XCTAssertEqual(reps.count, 1)
        XCTAssertEqual(reps[0].uti, "public.utf8-plain-text")
        XCTAssertEqual(String(decoding: reps[0].data, as: UTF8.self), "round trip")
    }

    func testDedupBumpsExistingItem() throws {
        let store = try makeTempStore()
        let first = try store.save(makeText("hello"), now: Date(timeIntervalSince1970: 1000))
        _ = try store.save(makeText("other"), now: Date(timeIntervalSince1970: 2000))
        let again = try store.save(makeText("hello"), now: Date(timeIntervalSince1970: 3000))

        XCTAssertEqual(first.id, again.id)
        let recent = try store.recentItems(limit: 10)
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent[0].plainText, "hello")
        XCTAssertEqual(recent[0].lastUsedAt, Date(timeIntervalSince1970: 3000))
        XCTAssertEqual(recent[0].createdAt, Date(timeIntervalSince1970: 1000))
    }

    func testDedupDoesNotDuplicateRepresentations() throws {
        let store = try makeTempStore()
        let a = try store.save(makeText("dup"))
        _ = try store.save(makeText("dup"))
        XCTAssertEqual(try store.representations(forItemID: a.id!).count, 1)
    }

    func testDifferentContentDifferentItems() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("a"))
        _ = try store.save(makeText("b"))
        XCTAssertEqual(try store.recentItems(limit: 10).count, 2)
    }

    func testDedupRefreshesRepresentationsAndSource() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("hello"))

        let styled = CapturedItem(
            kind: .richText, plainText: "hello", hashData: Data("hello".utf8),
            representations: [
                CapturedRepresentation(uti: "public.rtf", data: Data("rtf".utf8)),
                CapturedRepresentation(uti: "public.utf8-plain-text", data: Data("hello".utf8)),
            ],
            sourceBundleID: "com.other.app", sourceAppName: "OtherApp")
        let merged = try store.save(styled)

        let reps = try store.representations(forItemID: merged.id!)
        XCTAssertEqual(reps.map(\.uti), ["public.rtf", "public.utf8-plain-text"])
        XCTAssertEqual(merged.appBundleID, "com.other.app")
        XCTAssertEqual(merged.appName, "OtherApp")
        XCTAssertEqual(try store.recentItems(limit: 10).count, 1)
    }

    func testDedupRefreshCleansOrphanedBlob() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopyTests-\(UUID().uuidString)")
        let dbm = try DatabaseManager(directory: dir)
        let store = ItemStore(writer: dbm.writer, blobs: BlobStore(directory: dbm.blobsDirectory))

        let big = Data(repeating: 0xEE, count: 100_000)
        let first = CapturedItem(kind: .image, plainText: "Image", hashData: Data("same".utf8),
                                 representations: [CapturedRepresentation(uti: "public.png", data: big)],
                                 sourceBundleID: nil, sourceAppName: nil)
        let second = CapturedItem(kind: .image, plainText: "Image", hashData: Data("same".utf8),
                                  representations: [CapturedRepresentation(uti: "public.png", data: Data([0x01]))],
                                  sourceBundleID: nil, sourceAppName: nil)
        _ = try store.save(first)
        _ = try store.save(second)

        let blobFiles = try FileManager.default.contentsOfDirectory(atPath: dbm.blobsDirectory.path)
        XCTAssertEqual(blobFiles.count, 0, "old blob must be orphan-cleaned after refresh")
    }

    func testDedupPreservesFavicon() throws {
        let store = try makeTempStore()
        let url = "https://example.com"
        let link = CapturedItem(
            kind: .link, plainText: url, hashData: Data(url.utf8),
            representations: [CapturedRepresentation(uti: "public.utf8-plain-text", data: Data(url.utf8))],
            sourceBundleID: nil, sourceAppName: nil)
        let saved = try store.save(link)

        let faviconData = Data([0x89, 0x50, 0x4E, 0x47])
        try store.setFavicon(itemID: saved.id!, pngData: faviconData)

        // Re-copying the identical link hits the dedup branch, which used to wipe and
        // rebuild every representation for the item — including the favicon that
        // `setFavicon` stores out-of-band. It must survive the re-save.
        _ = try store.save(link)

        XCTAssertEqual(try store.favicon(forItemID: saved.id!), faviconData)
        let reps = try store.representations(forItemID: saved.id!)
        XCTAssertTrue(reps.contains { $0.uti == CopyPasteboard.faviconUTI })
    }

    func testReplaceContentClearsLinkTitle() throws {
        let store = try makeTempStore()
        let url = "https://example.com"
        let link = CapturedItem(
            kind: .link, plainText: url, hashData: Data(url.utf8),
            representations: [CapturedRepresentation(uti: "public.utf8-plain-text", data: Data(url.utf8))],
            sourceBundleID: nil, sourceAppName: nil)
        let saved = try store.save(link)
        try store.setLinkTitle(itemID: saved.id!, "Example Site")

        let replaced = try store.replaceContent(itemID: saved.id!, with: "https://other.example.com")

        XCTAssertNil(replaced.linkTitle, "stale linkTitle from the old URL must not survive replaceContent")
    }
}
