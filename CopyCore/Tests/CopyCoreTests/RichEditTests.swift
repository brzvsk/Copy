import XCTest
@testable import CopyCore

final class RichEditTests: XCTestCase {
    func testReplaceContentWithRichStoresRtfAndPlainReps() throws {
        let store = try makeTempStore()
        let saved = try store.save(makeText("plain original"))
        let rtfData = Data("{\\rtf1\\ansi hello}".utf8)

        let replaced = try store.replaceContent(itemID: saved.id!, rtfData: rtfData, plainText: "hello world")

        XCTAssertEqual(replaced.plainText, "hello world")
        XCTAssertEqual(replaced.kind, ItemKind.forText("hello world"))
        let reps = try store.representations(forItemID: replaced.id!)
        XCTAssertEqual(Set(reps.map(\.uti)), ["public.rtf", "public.utf8-plain-text"])
        let plainRep = reps.first { $0.uti == "public.utf8-plain-text" }
        XCTAssertEqual(plainRep.map { String(decoding: $0.data, as: UTF8.self) }, "hello world")
    }

    func testReplaceContentWithRichIsSearchableByPlainText() throws {
        let store = try makeTempStore()
        let saved = try store.save(makeText("placeholder"))
        let rtfData = Data("{\\rtf1\\ansi styled}".utf8)

        _ = try store.replaceContent(itemID: saved.id!, rtfData: rtfData, plainText: "searchable phrase here")

        let hits = try store.search("searchable")
        XCTAssertEqual(hits.map(\.plainText), ["searchable phrase here"])
    }

    func testReplaceContentWithRichRoundTripsRtfBytes() throws {
        let store = try makeTempStore()
        let saved = try store.save(makeText("original"))
        let rtfData = Data("{\\rtf1\\ansi\\b bold text\\b0}".utf8)

        let replaced = try store.replaceContent(itemID: saved.id!, rtfData: rtfData, plainText: "bold text")

        let reps = try store.representations(forItemID: replaced.id!)
        let rtfRep = reps.first { $0.uti == "public.rtf" }
        XCTAssertEqual(rtfRep?.data, rtfData)
    }
}
