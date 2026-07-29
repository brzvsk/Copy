import XCTest
@testable import CopyCore

private func makeImage(_ bytes: Data) -> CapturedItem {
    CapturedItem(
        kind: .image, plainText: "", hashData: bytes,
        representations: [CapturedRepresentation(uti: "public.png", data: bytes)],
        sourceBundleID: "com.test.app", sourceAppName: "TestApp"
    )
}

final class ArchiveIOTests: XCTestCase {
    func testExportThenImportIntoFreshStoreRestoresContentAndIsIdempotentOnReimport() throws {
        let (items, pinboards) = try makeTempStores()

        let plain = try items.save(makeText("plain body"))
        let favorite = try items.save(makeText("favorite body"))
        try items.setFavorite(itemID: favorite.id!, true)
        let titled = try items.createTextItem("titled body", title: "My Title")
        // A representation larger than ItemStore.inlineThreshold forces the blob-file
        // storage path, so this also proves blob-backed representations round-trip.
        let bigBlob = Data((0..<200_000).map { UInt8($0 % 256) })
        let image = try items.save(makeImage(bigBlob))

        let work = try pinboards.create(name: "Work", symbol: "briefcase")
        let snippets = try pinboards.create(name: "Snippets",
                                            symbol: "chevron.left.forwardslash.chevron.right",
                                            emoji: "✂️", tint: "blue")
        try pinboards.add(itemID: plain.id!, to: work.id!)
        try pinboards.add(itemID: titled.id!, to: work.id!)
        try pinboards.add(itemID: image.id!, to: snippets.id!)

        let data = try ArchiveIO.export(items: items, pinboards: pinboards)

        let (freshItems, freshPinboards) = try makeTempStores()
        let result = try ArchiveIO.importArchive(data, into: freshItems, pinboards: freshPinboards)

        XCTAssertEqual(result.itemsAdded, 4)
        XCTAssertEqual(result.pinboardsAdded, 2)

        let recent = try freshItems.recentItems(limit: 10)
        XCTAssertEqual(recent.count, 4)

        let restoredFavorite = recent.first { $0.contentHash == favorite.contentHash }
        XCTAssertEqual(restoredFavorite?.isFavorite, true)
        XCTAssertEqual(restoredFavorite?.plainText, "favorite body")

        let restoredTitled = recent.first { $0.contentHash == titled.contentHash }
        XCTAssertEqual(restoredTitled?.title, "My Title")
        XCTAssertEqual(restoredTitled?.plainText, "titled body")

        let restoredImage = recent.first { $0.contentHash == image.contentHash }
        XCTAssertEqual(restoredImage?.kind, .image)
        let restoredReps = try freshItems.representations(forItemID: restoredImage!.id!)
        XCTAssertEqual(restoredReps.count, 1)
        XCTAssertEqual(restoredReps[0].uti, "public.png")
        XCTAssertEqual(restoredReps[0].data, bigBlob)

        let restoredBoards = try freshPinboards.all()
        XCTAssertEqual(restoredBoards.map(\.name).sorted(), ["Snippets", "Work"])
        let restoredWork = restoredBoards.first { $0.name == "Work" }!
        let workMembers = try freshPinboards.items(in: restoredWork.id!)
        XCTAssertEqual(Set(workMembers.map(\.contentHash)), Set([plain.contentHash, titled.contentHash]))
        let restoredSnippets = restoredBoards.first { $0.name == "Snippets" }!
        XCTAssertEqual(restoredSnippets.emoji, "✂️")
        XCTAssertEqual(restoredSnippets.tint, "blue")
        let snippetMembers = try freshPinboards.items(in: restoredSnippets.id!)
        XCTAssertEqual(snippetMembers.map(\.contentHash), [image.contentHash])

        // Re-importing the same archive into the now-populated target must add nothing.
        let reimportResult = try ArchiveIO.importArchive(data, into: freshItems, pinboards: freshPinboards)
        XCTAssertEqual(reimportResult.itemsAdded, 0)
        XCTAssertEqual(reimportResult.pinboardsAdded, 0)
        XCTAssertEqual(try freshItems.recentItems(limit: 10).count, 4)
        XCTAssertEqual(try freshPinboards.all().count, 2)
    }

    func testImportSkipsAnItemAlreadyPresentInTheTargetByContentHash() throws {
        let (items, pinboards) = try makeTempStores()
        _ = try items.save(makeText("shared body"))
        let data = try ArchiveIO.export(items: items, pinboards: pinboards)

        // The target already has an item with the same content hash (e.g. the user
        // never wiped history before importing an old backup) — dedup must still hold.
        let (target, targetPinboards) = try makeTempStores()
        _ = try target.save(makeText("shared body"))
        let result = try ArchiveIO.importArchive(data, into: target, pinboards: targetPinboards)
        XCTAssertEqual(result.itemsAdded, 0)
        XCTAssertEqual(try target.recentItems(limit: 10).count, 1)
    }

    func testArchiveRoundTripsThroughJSONEncodingIntact() throws {
        let (items, pinboards) = try makeTempStores()
        _ = try items.save(makeText("hello archive"))
        let data = try ArchiveIO.export(items: items, pinboards: pinboards)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(ClipArchive.self, from: data)
        XCTAssertEqual(archive.version, ArchiveIO.currentVersion)
        XCTAssertEqual(archive.items.count, 1)
        XCTAssertEqual(archive.items[0].plainText, "hello archive")
    }
}
