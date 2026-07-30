import XCTest
@testable import CopyCore

final class ImageRotateTests: XCTestCase {
    private func makeImageItem(_ store: ItemStore, bytes: [UInt8], uti: String = "public.jpeg") throws -> ClipItem {
        let data = Data(bytes)
        let captured = CapturedItem(
            kind: .image, plainText: "", hashData: data,
            representations: [CapturedRepresentation(uti: uti, data: data)],
            sourceBundleID: "com.test.app", sourceAppName: "TestApp"
        )
        return try store.save(captured)
    }

    func testReplaceImageRepresentationSwapsBytesRehashesAndResizes() throws {
        let store = try makeTempStore()
        let saved = try makeImageItem(store, bytes: [0x01, 0x02, 0x03, 0x04])
        let originalHash = saved.contentHash

        let rotated = Data([0x09, 0x08, 0x07, 0x06, 0x05])
        let updated = try store.replaceImageRepresentation(itemID: saved.id!, data: rotated, uti: "public.jpeg")

        XCTAssertEqual(updated.kind, .image)
        XCTAssertNotEqual(updated.contentHash, originalHash)
        XCTAssertEqual(updated.contentHash, BlobStore.key(for: rotated))
        XCTAssertEqual(updated.sizeBytes, rotated.count)
        let reps = try store.representations(forItemID: updated.id!)
        XCTAssertEqual(reps.count, 1)
        XCTAssertEqual(reps.first?.data, rotated)
        XCTAssertEqual(reps.first?.uti, "public.jpeg")
    }

    func testReplaceImageRepresentationClearsStaleOCRText() throws {
        let store = try makeTempStore()
        let saved = try makeImageItem(store, bytes: [0x11, 0x22, 0x33])
        try store.setRecognizedText(itemID: saved.id!, "words from the original image")

        let updated = try store.replaceImageRepresentation(itemID: saved.id!, data: Data([0x44, 0x55]), uti: "public.jpeg")

        let refetched = try store.item(contentHash: updated.contentHash)
        XCTAssertNil(refetched?.recognizedText, "OCR text is stale after a rotate and must be cleared")
    }
}
