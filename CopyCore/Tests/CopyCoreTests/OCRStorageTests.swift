import XCTest
@testable import CopyCore

final class OCRStorageTests: XCTestCase {
    func testSetRecognizedTextMakesImageItemSearchable() throws {
        let store = try makeTempStore()
        let imageItem = CapturedItem(
            kind: .image, plainText: "Image", hashData: Data("img-1".utf8),
            representations: [CapturedRepresentation(uti: "public.png", data: Data([0x89, 0x50]))],
            sourceBundleID: nil, sourceAppName: nil
        )
        let saved = try store.save(imageItem)

        try store.setRecognizedText(itemID: saved.id!, "invoice total 42")
        let hits = try store.search("invoice")
        XCTAssertEqual(hits.map(\.id), [saved.id])
        XCTAssertEqual(hits.first?.recognizedText, "invoice total 42")
    }

    func testRecognizedTextRoundTrips() throws {
        let store = try makeTempStore()
        let imageItem = CapturedItem(
            kind: .image, plainText: "Image", hashData: Data("img-2".utf8),
            representations: [CapturedRepresentation(uti: "public.png", data: Data([0x89, 0x50]))],
            sourceBundleID: nil, sourceAppName: nil
        )
        let saved = try store.save(imageItem)

        try store.setRecognizedText(itemID: saved.id!, "warehouse code 99")
        let fetched = try store.recognizedText(forItemID: saved.id!)
        XCTAssertEqual(fetched, "warehouse code 99")
    }

    func testSetRecognizedTextOverwritesPriorValue() throws {
        let store = try makeTempStore()
        let imageItem = CapturedItem(
            kind: .image, plainText: "Image", hashData: Data("img-3".utf8),
            representations: [CapturedRepresentation(uti: "public.png", data: Data([0x89, 0x50]))],
            sourceBundleID: nil, sourceAppName: nil
        )
        let saved = try store.save(imageItem)

        try store.setRecognizedText(itemID: saved.id!, "first value")
        var hits = try store.search("first")
        XCTAssertEqual(hits.map(\.id), [saved.id])

        try store.setRecognizedText(itemID: saved.id!, "second value")
        XCTAssertEqual(try store.recognizedText(forItemID: saved.id!), "second value")
        hits = try store.search("second")
        XCTAssertEqual(hits.map(\.id), [saved.id])
        hits = try store.search("first")
        XCTAssertEqual(hits.count, 0, "prior value should not be searchable after overwrite")
    }

    func testRecognizedTextNilBeforeSetting() throws {
        let store = try makeTempStore()
        let imageItem = CapturedItem(
            kind: .image, plainText: "Image", hashData: Data("img-4".utf8),
            representations: [CapturedRepresentation(uti: "public.png", data: Data([0x89, 0x50]))],
            sourceBundleID: nil, sourceAppName: nil
        )
        let saved = try store.save(imageItem)

        let beforeSetting = try store.recognizedText(forItemID: saved.id!)
        XCTAssertNil(beforeSetting)
    }
}
