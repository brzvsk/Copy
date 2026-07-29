import XCTest
@testable import CopyCore

final class SpyPasteboard: PasteboardWriting {
    var written: [(representations: [CapturedRepresentation], marker: String)] = []
    func write(_ representations: [CapturedRepresentation], marker: String) {
        written.append((representations, marker))
    }
}

final class SpyKeyPoster: KeyEventPosting {
    var postCount = 0
    func postCommandV() { postCount += 1 }
}

final class PasteServiceTests: XCTestCase {
    func testPlaceWritesAllRepresentationsWithMarker() {
        let pasteboard = SpyPasteboard()
        let service = PasteService(pasteboard: pasteboard, keyPoster: SpyKeyPoster())
        let reps = [
            CapturedRepresentation(uti: "public.rtf", data: Data("rtf".utf8)),
            CapturedRepresentation(uti: "public.utf8-plain-text", data: Data("plain".utf8)),
        ]
        service.place(reps, plainTextOnly: false)
        XCTAssertEqual(pasteboard.written.count, 1)
        XCTAssertEqual(pasteboard.written[0].representations, reps)
        XCTAssertEqual(pasteboard.written[0].marker, CopyPasteboard.selfMarkerType)
    }

    func testPlacePlainTextOnlyFiltersToPlainRepresentation() {
        let pasteboard = SpyPasteboard()
        let service = PasteService(pasteboard: pasteboard, keyPoster: SpyKeyPoster())
        let plain = CapturedRepresentation(uti: "public.utf8-plain-text", data: Data("plain".utf8))
        let reps = [CapturedRepresentation(uti: "public.rtf", data: Data("rtf".utf8)), plain]
        service.place(reps, plainTextOnly: true)
        XCTAssertEqual(pasteboard.written[0].representations, [plain])
    }

    func testSendPasteKeystrokePostsCommandV() {
        let poster = SpyKeyPoster()
        let service = PasteService(pasteboard: SpyPasteboard(), keyPoster: poster)
        service.sendPasteKeystroke()
        XCTAssertEqual(poster.postCount, 1)
    }
}
