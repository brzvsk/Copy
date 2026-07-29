import AppKit
import Quartz
import CopyCore

/// Drives the system Quick Look panel (`QLPreviewPanel`) for `.file` item cards, so a
/// copied file previews the same way it would in Finder (icon, media playback, PDF
/// pages, and so on) instead of Copy's own plain-text preview.
///
/// `QLPreviewPanel` is a single, process-wide instance that hands control to whichever
/// object in the responder chain claims it via `acceptsPreviewPanelControl(_:)`. This
/// controller is invoked directly (a context-menu action or a button in `PreviewPane`),
/// so it sets `dataSource`/`delegate` itself before showing the panel; `AppDelegate`
/// also forwards the three responder-chain methods here (see `AppDelegate+QuickLook`)
/// so the panel keeps its content if AppKit re-resolves the controller on its own —
/// `AppDelegate` is always reachable via `NSApp.delegate`, even though the shelf's own
/// `KeyablePanel` isn't a normal document window.
@MainActor
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()

    private var urls: [URL] = []

    var hasContent: Bool { !urls.isEmpty }

    private override init() {}

    /// Shows the system preview panel for the given file URLs. No-ops if empty (e.g.
    /// every underlying file has since been moved or deleted).
    func preview(_ urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Called back from `AppDelegate.endPreviewPanelControl(_:)` once the panel gives
    /// up control, so a stale URL list can't leak into the next `hasContent` check.
    func clear() {
        urls = []
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard urls.indices.contains(index) else { return nil }
        return urls[index] as NSURL
    }
}

extension QuickLookController {
    /// Reconstructs a `.file` item's underlying file URL(s) from its `public.file-url`
    /// representations (one per file for multi-file copies), keeping only paths that
    /// still exist on disk — a moved or deleted source file just quietly drops out
    /// rather than handing Quick Look a stale path.
    static func fileURLs(for item: ClipItem, store: ItemStore) -> [URL] {
        guard item.kind == .file, let id = item.id,
              let reps = try? store.representations(forItemID: id) else { return [] }
        return reps
            .filter { $0.uti == "public.file-url" }
            .compactMap { URL(dataRepresentation: $0.data, relativeTo: nil) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
