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
}
