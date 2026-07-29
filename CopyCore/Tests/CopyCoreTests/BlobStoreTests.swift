import XCTest
@testable import CopyCore

final class BlobStoreTests: XCTestCase {
    func testContentAddressing() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlobTests-\(UUID().uuidString)")
        let blobs = BlobStore(directory: dir)
        let data = Data("same content".utf8)
        let k1 = try blobs.store(data)
        let k2 = try blobs.store(data)
        XCTAssertEqual(k1, k2)
        XCTAssertEqual(blobs.data(forKey: k1), data)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(files.count, 1)
    }

    func testLargeRepresentationGoesToBlobAndRoundTrips() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopyTests-\(UUID().uuidString)")
        let dbm = try DatabaseManager(directory: dir)
        let blobs = BlobStore(directory: dbm.blobsDirectory)
        let store = ItemStore(writer: dbm.writer, blobs: blobs)

        let big = Data(repeating: 0xAB, count: 100_000)
        let captured = CapturedItem(
            kind: .image, plainText: "Image", hashData: big,
            representations: [CapturedRepresentation(uti: "public.png", data: big)],
            sourceBundleID: nil, sourceAppName: nil)
        let saved = try store.save(captured)

        let blobFiles = try FileManager.default.contentsOfDirectory(atPath: dbm.blobsDirectory.path)
        XCTAssertEqual(blobFiles.count, 1)

        let reps = try store.representations(forItemID: saved.id!)
        XCTAssertEqual(reps, [CapturedRepresentation(uti: "public.png", data: big)])
    }

    func testDeleteRemovesOrphanedBlob() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopyTests-\(UUID().uuidString)")
        let dbm = try DatabaseManager(directory: dir)
        let store = ItemStore(writer: dbm.writer, blobs: BlobStore(directory: dbm.blobsDirectory))

        let big = Data(repeating: 0xCD, count: 100_000)
        let captured = CapturedItem(
            kind: .image, plainText: "Image", hashData: big,
            representations: [CapturedRepresentation(uti: "public.png", data: big)],
            sourceBundleID: nil, sourceAppName: nil)
        let saved = try store.save(captured)
        try store.delete(itemID: saved.id!)

        let blobFiles = try FileManager.default.contentsOfDirectory(atPath: dbm.blobsDirectory.path)
        XCTAssertEqual(blobFiles.count, 0)
    }
}
