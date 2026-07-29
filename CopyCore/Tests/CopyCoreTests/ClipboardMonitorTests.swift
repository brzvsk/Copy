import XCTest
@testable import CopyCore

final class FakePasteboard: PasteboardReading {
    var changeCount = 0
    var typeIDs: [String] = []
    var dataByUTI: [String: Data] = [:]
    var stringValue: String?
    var urls: [URL] = []
    var colorHexValue: String?

    func typeIdentifiers() -> [String] { typeIDs }
    func data(forUTI uti: String) -> Data? { dataByUTI[uti] }
    func string() -> String? { stringValue }
    func fileURLs() -> [URL] { urls }
    func colorHex() -> String? { colorHexValue }

    func putText(_ s: String, extraTypes: [String] = []) {
        changeCount += 1
        typeIDs = ["public.utf8-plain-text"] + extraTypes
        stringValue = s
        dataByUTI = [:]
        urls = []
        colorHexValue = nil
    }

    func putImage(_ data: Data) {
        changeCount += 1
        typeIDs = ["public.png"]
        stringValue = nil
        dataByUTI = ["public.png": data]
        urls = []
        colorHexValue = nil
    }

    func putFiles(_ fileURLs: [URL]) {
        changeCount += 1
        typeIDs = ["public.file-url"]
        stringValue = nil
        dataByUTI = [:]
        urls = fileURLs
        colorHexValue = nil
    }

    func putColor(_ hex: String) {
        changeCount += 1
        typeIDs = [CopyPasteboard.colorType]
        stringValue = nil
        dataByUTI = [:]
        urls = []
        colorHexValue = hex
    }

    func putImageBoth(png: Data, tiff: Data) {
        changeCount += 1
        typeIDs = ["public.png", "public.tiff"]
        stringValue = nil
        dataByUTI = ["public.png": png, "public.tiff": tiff]
        urls = []
        colorHexValue = nil
    }
}

final class ClipboardMonitorTests: XCTestCase {
    var pasteboard: FakePasteboard!
    var captured: [CapturedItem]!
    var monitor: ClipboardMonitor!

    override func setUp() {
        super.setUp()
        pasteboard = FakePasteboard()
        captured = []
        monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            rules: RulesEngine(excludedBundleIDs: ["com.excluded.app"]),
            frontmostApp: { ("com.apple.Safari", "Safari") },
            onCapture: { [weak self] item in self?.captured.append(item) }
        )
    }

    func testNoChangeNoCapture() {
        monitor.checkNow()
        monitor.checkNow()
        XCTAssertEqual(captured.count, 0)
    }

    func testCapturesTextOnce() {
        pasteboard.putText("hello world")
        monitor.checkNow()
        monitor.checkNow() // same changeCount — must not re-capture
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured[0].kind, .text)
        XCTAssertEqual(captured[0].plainText, "hello world")
        XCTAssertEqual(captured[0].sourceBundleID, "com.apple.Safari")
        XCTAssertEqual(captured[0].representations.map(\.uti), ["public.utf8-plain-text"])
    }

    func testDetectsLink() {
        pasteboard.putText("https://example.com")
        monitor.checkNow()
        XCTAssertEqual(captured[0].kind, .link)
    }

    func testCapturesImage() {
        pasteboard.putImage(Data([0x89, 0x50, 0x4E, 0x47]))
        monitor.checkNow()
        XCTAssertEqual(captured[0].kind, .image)
        XCTAssertEqual(captured[0].representations.map(\.uti), ["public.png"])
    }

    func testCapturesFiles() {
        pasteboard.putFiles([URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")])
        monitor.checkNow()
        XCTAssertEqual(captured[0].kind, .file)
        XCTAssertEqual(captured[0].plainText, "a.txt\nb.txt")
        XCTAssertEqual(captured[0].representations.count, 2)
    }

    func testSkipsConcealed() {
        pasteboard.putText("secret", extraTypes: ["org.nspasteboard.ConcealedType"])
        monitor.checkNow()
        XCTAssertEqual(captured.count, 0)
    }

    func testSkipsOwnMarker() {
        pasteboard.putText("mine", extraTypes: [CopyPasteboard.selfMarkerType])
        monitor.checkNow()
        XCTAssertEqual(captured.count, 0)
    }

    func testPausedSkipsButTracksChangeCount() {
        monitor.isPaused = true
        pasteboard.putText("while paused")
        monitor.checkNow()
        XCTAssertEqual(captured.count, 0)
        monitor.isPaused = false
        monitor.checkNow() // change already consumed — still nothing
        XCTAssertEqual(captured.count, 0)
        pasteboard.putText("after resume")
        monitor.checkNow()
        XCTAssertEqual(captured.count, 1)
    }

    func testRichTextKind() {
        pasteboard.putText("styled")
        pasteboard.dataByUTI["public.rtf"] = Data("rtf-bytes".utf8)
        pasteboard.typeIDs.append("public.rtf")
        monitor.checkNow()
        XCTAssertEqual(captured[0].kind, .richText)
        XCTAssertEqual(Set(captured[0].representations.map(\.uti)), ["public.rtf", "public.utf8-plain-text"])
    }

    func testCapturesColor() {
        pasteboard.putColor("#FF8800")
        monitor.checkNow()
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured[0].kind, .color)
        XCTAssertEqual(captured[0].plainText, "#FF8800")
        XCTAssertEqual(captured[0].representations.map(\.uti), [CopyPasteboard.colorType])
        XCTAssertEqual(String(decoding: captured[0].representations[0].data, as: UTF8.self), "#FF8800")
    }

    func testCapturesBothImageRepresentations() {
        let png = Data([0x89, 0x50])
        let tiff = Data([0x4D, 0x4D])
        pasteboard.putImageBoth(png: png, tiff: tiff)
        monitor.checkNow()
        XCTAssertEqual(captured[0].kind, .image)
        XCTAssertEqual(captured[0].representations.map(\.uti), ["public.png", "public.tiff"])
        XCTAssertEqual(captured[0].hashData, png)
    }

    func testOversizedItemIsSkipped() {
        pasteboard.putImage(Data(count: ClipboardMonitor.maxRepresentationBytes + 1))
        monitor.checkNow()
        XCTAssertEqual(captured.count, 0)
        pasteboard.putText("small after big")
        monitor.checkNow()
        XCTAssertEqual(captured.count, 1)
    }
}
