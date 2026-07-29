import AppKit
import ApplicationServices
import CopyCore
import SwiftUI

@MainActor
final class AppCoordinator {
    let store: ItemStore
    let pinboardStore: PinboardStore
    let settings: SettingsStore
    private let monitor: ClipboardMonitor
    private let pasteService: PasteService
    private let persistQueue = DispatchQueue(label: "com.tarikbc.copy.persist", qos: .utility)
    private let saveErrors = SaveErrorReporter()
    private var retentionTimer: DispatchSourceTimer?
    private(set) var isPaused = false
    private(set) lazy var shelfViewModel = ShelfViewModel(store: store, pinboardStore: pinboardStore)
    private(set) lazy var linkFetcher = LinkMetadataFetcher(store: store)

    private lazy var pasteStackModel: PasteStackModel = {
        let model = PasteStackModel(store: store)
        model.onActiveChange = { [weak self] isActive in
            self?.pasteStackController.syncVisibility(to: isActive)
        }
        return model
    }()
    private lazy var pasteStackController = PasteStackController(model: pasteStackModel)

    /// How often the retention pruner re-runs while the app stays open.
    private static let retentionInterval: TimeInterval = 12 * 60 * 60

    private lazy var shelfController: ShelfPanelController = {
        let controller = ShelfPanelController { [weak self] in
            guard let self else { return NSView() }
            return NSHostingView(rootView: ShelfRootView(viewModel: self.shelfViewModel))
        }
        controller.onDidHide = { [weak self] in
            self?.shelfViewModel.clearTransientState()
        }
        controller.onKeyEvent = { [weak self, weak controller] event in
            guard let self, let controller else { return false }
            let viewModel = self.shelfViewModel
            // While the edit sheet is up, let its own window handle every key (arrows,
            // space, escape, return) instead of the shelf's global shortcuts — this
            // monitor is app-wide and fires before the sheet's responder chain would see
            // the event otherwise.
            guard viewModel.editingItem == nil, !viewModel.pinboardPopoverShown else { return false }
            // ⌘1 → history tab, ⌘2...⌘9 → nth pinboard. Checked before keyCode routing
            // so the digit keys never fall through to other handlers.
            if event.modifierFlags.contains(.command),
               let chars = event.charactersIgnoringModifiers, chars.count == 1,
               let digit = chars.first, let digitValue = digit.wholeNumberValue,
               (1...9).contains(digitValue) {
                if digitValue == 1 {
                    viewModel.tab = .history
                } else {
                    let index = digitValue - 2
                    if viewModel.pinboards.indices.contains(index), let id = viewModel.pinboards[index].id {
                        viewModel.tab = .pinboard(id)
                    }
                }
                return true
            }
            switch event.keyCode {
            case 123: // left arrow
                viewModel.moveSelection(-1)
                return true
            case 124: // right arrow
                viewModel.moveSelection(1)
                return true
            case 53: // escape
                if viewModel.previewShown {
                    viewModel.previewShown = false
                } else if !viewModel.query.isEmpty {
                    viewModel.query = ""
                } else {
                    controller.hide(restoreFocus: true)
                }
                return true
            case 36: // return
                viewModel.pasteSelection(plain: event.modifierFlags.contains(.option))
                return true
            case 51 where event.modifierFlags.contains(.command): // cmd-delete
                viewModel.deleteSelection()
                return true
            case 14 where event.modifierFlags.contains(.command): // cmd-E — edit primary item
                viewModel.beginEdit()
                return true
            case 49 where viewModel.query.isEmpty: // space previews in browse mode
                viewModel.previewShown.toggle()
                return true
            default:
                return false
            }
        }
        shelfViewModel.onPaste = { [weak self, weak controller] item, plain in
            controller?.hide(restoreFocus: true)
            self?.pasteFromShelf(item, plainTextOnly: plain)
        }
        shelfViewModel.onAddToPasteStack = { [weak self] item in
            self?.addToPasteStack(item)
        }
        shelfViewModel.onPasteMultiple = { [weak self, weak controller] joined in
            controller?.hide(restoreFocus: true)
            guard let self else { return }
            self.pasteService.place(
                [CapturedRepresentation(uti: "public.utf8-plain-text", data: Data(joined.utf8))],
                plainTextOnly: false)
            guard AXIsProcessTrusted() else {
                HUD.show("Press ⌘V to paste")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [pasteService = self.pasteService] in
                pasteService.sendPasteKeystroke()
            }
        }
        return controller
    }()

    private lazy var settingsWindowController = SettingsWindowController(settings: settings)

    init() throws {
        let database = try DatabaseManager.makeDefault()
        let blobs = BlobStore(directory: database.blobsDirectory)
        let store = ItemStore(writer: database.writer, blobs: blobs)
        self.store = store
        self.pinboardStore = PinboardStore(writer: database.writer)
        self.pasteService = PasteService(pasteboard: NSPasteboard.general,
                                         keyPoster: CGKeyEventPoster())
        let settings = SettingsStore()
        self.settings = settings
        let linkFetcher = LinkMetadataFetcher(store: store)
        let reporter = saveErrors
        self.monitor = ClipboardMonitor(
            pasteboard: NSPasteboard.general,
            rules: RulesEngine(excludedBundleIDs: Set(settings.excludedBundleIDs)),
            frontmostApp: {
                let app = NSWorkspace.shared.frontmostApplication
                return (app?.bundleIdentifier, app?.localizedName)
            },
            onCapture: { [persistQueue, linkFetcher, settings] captured in
                persistQueue.async {
                    do {
                        let saved = try store.save(captured)
                        DispatchQueue.main.async {
                            linkFetcher.fetchIfNeeded(for: saved, enabled: settings.fetchLinkPreviews)
                        }
                    } catch {
                        reporter.report(error)
                    }
                }
            }
        )
        self.linkFetcher = linkFetcher
        settings.onRulesChange = { [weak self] excludedBundleIDs in
            self?.monitor.rules = RulesEngine(excludedBundleIDs: excludedBundleIDs)
        }
    }

    func start() {
        monitor.start()
        runRetentionPrune()
        scheduleRetentionTimer()
    }

    /// Prunes items past the configured retention window on the persist queue,
    /// always sparing favorites and pinboard members (`ItemStore.prune` invariant).
    private func runRetentionPrune() {
        let cutoff = settings.retention.cutoff
        let store = self.store
        persistQueue.async {
            do {
                let deleted = try store.prune(olderThan: cutoff, maxItems: nil)
                if deleted > 0 {
                    NSLog("Copy: retention pruning removed \(deleted) item(s)")
                }
            } catch {
                NSLog("Copy: retention pruning failed: \(error)")
            }
        }
    }

    private func scheduleRetentionTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.retentionInterval, repeating: Self.retentionInterval)
        timer.setEventHandler { [weak self] in self?.runRetentionPrune() }
        timer.resume()
        retentionTimer = timer
    }

    /// Shows the Settings window (see `SettingsWindowController` for why this is a
    /// window we manage directly instead of going through SwiftUI's `Settings` scene).
    func openSettings() {
        settingsWindowController.show()
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

    /// Enqueues `item` into the Paste Stack (activating the palette if it wasn't
    /// already) from the card context menu's "Add to Paste Stack" action. The palette
    /// re-fits its own size to the new row via `PasteStackView.onContentChange`, so
    /// there's no need to poke the controller directly here.
    func addToPasteStack(_ item: ClipItem) {
        pasteStackModel.enqueue(item)
        HUD.show("Added to Paste Stack")
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
        pasteFromShelf(item, plainTextOnly: false)
    }

    func pasteFromShelf(_ item: ClipItem, plainTextOnly: Bool) {
        guard let id = item.id,
              let reps = try? store.representations(forItemID: id),
              !reps.isEmpty else {
            HUD.show("Item unavailable")
            return
        }
        pasteService.place(reps, plainTextOnly: plainTextOnly)
        try? store.touch(itemID: id)

        guard AXIsProcessTrusted() else {
            HUD.show("Press ⌘V to paste")
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
