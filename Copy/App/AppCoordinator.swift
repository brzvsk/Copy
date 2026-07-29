import AppKit
import ApplicationServices
import CopyCore
import SwiftUI

@MainActor
final class AppCoordinator {
    let store: ItemStore
    private let monitor: ClipboardMonitor
    private let pasteService: PasteService
    private(set) var isPaused = false
    private lazy var shelfController = ShelfPanelController { [weak self] in
        _ = self
        return NSHostingView(rootView: ShelfPlaceholderView())
    }

    init() throws {
        let database = try DatabaseManager.makeDefault()
        let blobs = BlobStore(directory: database.blobsDirectory)
        let store = ItemStore(writer: database.writer, blobs: blobs)
        self.store = store
        self.pasteService = PasteService(pasteboard: NSPasteboard.general,
                                         keyPoster: CGKeyEventPoster())
        self.monitor = ClipboardMonitor(
            pasteboard: NSPasteboard.general,
            rules: RulesEngine(),
            frontmostApp: {
                let app = NSWorkspace.shared.frontmostApplication
                return (app?.bundleIdentifier, app?.localizedName)
            },
            onCapture: { captured in
                do {
                    try store.save(captured)
                } catch {
                    NSLog("Copy: failed to save clipboard item: \(error)")
                }
            }
        )
    }

    func start() {
        monitor.start()
    }

    func toggleShelf() {
        shelfController.toggle()
    }

    func togglePause() {
        isPaused.toggle()
        monitor.isPaused = isPaused
    }

    func recentItems() -> [ClipItem] {
        (try? store.recentItems(limit: 10)) ?? []
    }

    func clearHistory() {
        do {
            try store.clearHistory(keepFavorites: true)
        } catch {
            NSLog("Copy: failed to clear history: \(error)")
        }
    }

    /// Puts the item on the clipboard and pastes it into the frontmost app.
    /// Without Accessibility, the item stays on the clipboard for a manual ⌘V.
    func paste(_ item: ClipItem) {
        guard let id = item.id,
              let reps = try? store.representations(forItemID: id),
              !reps.isEmpty else { return }
        pasteService.place(reps, plainTextOnly: false)
        try? store.touch(itemID: id)

        guard AXIsProcessTrusted() else {
            promptForAccessibility()
            return
        }
        // Give the menu time to close so the keystroke lands in the frontmost app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [pasteService] in
            pasteService.sendPasteKeystroke()
        }
    }

    private func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
