import XCTest
@testable import CopyCore

private func makeImage(_ bytes: Data) -> CapturedItem {
    CapturedItem(
        kind: .image, plainText: "", hashData: bytes,
        representations: [CapturedRepresentation(uti: "public.png", data: bytes)],
        sourceBundleID: "com.test.app", sourceAppName: "TestApp"
    )
}

private func makeLink(_ url: String) -> CapturedItem {
    CapturedItem(
        kind: .link, plainText: url, hashData: Data(url.utf8),
        representations: [CapturedRepresentation(uti: "public.utf8-plain-text", data: Data(url.utf8))],
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
        XCTAssertEqual(result.itemsSkipped, 0)
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
        XCTAssertEqual(reimportResult.itemsSkipped, 0)
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

    func testLinkTitleSurvivesExportImportRoundTrip() throws {
        let (items, pinboards) = try makeTempStores()
        let link = try items.save(makeLink("https://example.com"))
        try items.setLinkTitle(itemID: link.id!, "Example Domain")

        let data = try ArchiveIO.export(items: items, pinboards: pinboards)
        let (freshItems, freshPinboards) = try makeTempStores()
        let result = try ArchiveIO.importArchive(data, into: freshItems, pinboards: freshPinboards)
        XCTAssertEqual(result.itemsAdded, 1)

        let restored = try freshItems.recentItems(limit: 10).first { $0.contentHash == link.contentHash }
        XCTAssertEqual(restored?.linkTitle, "Example Domain")
        XCTAssertEqual(try freshItems.search("Example").map(\.id), [restored?.id])
    }

    /// Regression for a crash: pinboard names have no uniqueness constraint, so a
    /// target store can trivially already contain two pinboards sharing a name before
    /// import ever runs. The by-name dedup dictionary must tolerate that instead of
    /// trapping on a duplicate key.
    func testImportDoesNotCrashWhenTargetHasDuplicatePinboardNamesAndMergesMembership() throws {
        let (sourceItems, sourcePinboards) = try makeTempStores()
        let member = try sourceItems.save(makeText("filed item"))
        let sourceBoard = try sourcePinboards.create(name: "Work", symbol: "briefcase")
        try sourcePinboards.add(itemID: member.id!, to: sourceBoard.id!)
        let data = try ArchiveIO.export(items: sourceItems, pinboards: sourcePinboards)

        let (targetItems, targetPinboards) = try makeTempStores()
        let workA = try targetPinboards.create(name: "Work", symbol: "briefcase")
        _ = try targetPinboards.create(name: "Work", symbol: "folder")

        let result = try ArchiveIO.importArchive(data, into: targetItems, pinboards: targetPinboards)
        XCTAssertEqual(result.pinboardsAdded, 0, "both \"Work\" boards already existed; nothing new should be created")

        let restoredMember = try targetItems.recentItems(limit: 10).first { $0.contentHash == member.contentHash }
        XCTAssertNotNil(restoredMember)
        let workAMembers = try targetPinboards.items(in: workA.id!)
        XCTAssertEqual(workAMembers.map(\.contentHash), [member.contentHash],
                       "membership should merge into one matching \"Work\" board rather than crashing")
    }

    /// An archive item with an unrecognized `kind` (e.g. written by a future Copy
    /// version that added a new item kind) must be skipped, not abort the whole import.
    func testImportSkipsAnItemWithAnUnrecognizedKindAndReportsIt() throws {
        let (items, pinboards) = try makeTempStores()
        let good = try items.save(makeText("valid item"))
        let data = try ArchiveIO.export(items: items, pinboards: pinboards)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(ClipArchive.self, from: data)
        let bogus = ArchivedItem(
            kind: "holobeam", plainText: "mystery", title: nil, linkTitle: nil, recognizedText: nil,
            appName: nil, appBundleID: nil, createdAt: Date(), lastUsedAt: Date(),
            contentHash: "bogus-hash", isFavorite: false, representations: [])
        let spliced = ClipArchive(version: archive.version, exportedAt: archive.exportedAt,
                                  items: archive.items + [bogus], pinboards: archive.pinboards)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let splicedData = try encoder.encode(spliced)

        let (target, targetPinboards) = try makeTempStores()
        let result = try ArchiveIO.importArchive(splicedData, into: target, pinboards: targetPinboards)
        XCTAssertEqual(result.itemsAdded, 1)
        XCTAssertEqual(result.itemsSkipped, 1)
        XCTAssertEqual(try target.recentItems(limit: 10).map(\.contentHash), [good.contentHash])
    }
}
