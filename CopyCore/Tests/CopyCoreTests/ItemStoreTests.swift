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

    func testRecentOrderedByLastUsedDescending() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("first"), now: Date(timeIntervalSince1970: 1000))
        _ = try store.save(makeText("second"), now: Date(timeIntervalSince1970: 2000))
        let recent = try store.recentItems(limit: 10)
        XCTAssertEqual(recent.map(\.plainText), ["second", "first"])
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
}
