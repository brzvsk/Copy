import AppKit

public protocol PasteboardWriting {
    func write(_ representations: [CapturedRepresentation], marker: String)
}

public protocol KeyEventPosting {
    func postCommandV()
}

extension NSPasteboard: PasteboardWriting {
    public func write(_ representations: [CapturedRepresentation], marker: String) {
        clearContents()

        let urls = representations
            .filter { $0.uti == "public.file-url" }
            .compactMap { URL(dataRepresentation: $0.data, relativeTo: nil) }
        if !urls.isEmpty {
            writeObjects(urls as [NSURL])
            setData(Data(), forType: NSPasteboard.PasteboardType(marker))
            return
        }

        let item = NSPasteboardItem()
        for rep in representations {
            item.setData(rep.data, forType: NSPasteboard.PasteboardType(rep.uti))
        }
        item.setData(Data(), forType: NSPasteboard.PasteboardType(marker))
        writeObjects([item])
    }
}

public struct CGKeyEventPoster: KeyEventPosting {
    public init() {}

    public func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9 // kVK_ANSI_V
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

public final class PasteService {
    private let pasteboard: PasteboardWriting
    private let keyPoster: KeyEventPosting

    public init(pasteboard: PasteboardWriting, keyPoster: KeyEventPosting) {
        self.pasteboard = pasteboard
        self.keyPoster = keyPoster
    }

    public func place(_ representations: [CapturedRepresentation], plainTextOnly: Bool) {
        var reps = representations
        if plainTextOnly,
           let plain = representations.first(where: { $0.uti == "public.utf8-plain-text" }) {
            reps = [plain]
        }
        pasteboard.write(reps, marker: CopyPasteboard.selfMarkerType)
    }

    public func sendPasteKeystroke() {
        keyPoster.postCommandV()
    }
}
