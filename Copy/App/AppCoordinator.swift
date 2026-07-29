import AppKit
import ApplicationServices
import CopyCore
import KeyboardShortcuts
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
    private(set) lazy var ocrController = OCRController(store: store)
    private(set) lazy var archiveController = ArchiveController(store: store, pinboardStore: pinboardStore)

    /// Assigned eagerly in `init()` (from a local, not `self.pasteStackModel`) so the
    /// monitor's `onCapture` closure can capture it directly for the auto-enqueue-while-
    /// active behavior — `self` isn't fully initialized yet at that point in `init()`,
    /// but a plain local reference to this same instance is fine to capture. Its
    /// `onActiveChange` handler is wired afterward, once `self` is safe to capture.
    private let pasteStackModel: PasteStackModel
    private lazy var pasteStackController = PasteStackController(model: pasteStackModel)
    private lazy var pasteStackEngine = PasteStackEngine(onIntercept: { [weak self] in
        self?.pasteNextViaEngine()
    })

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
            // While the edit/create/rename sheet is up, let its own window handle every
            // key (arrows, space, escape, return) instead of the shelf's global
            // shortcuts — this monitor is app-wide and fires before the sheet's
            // responder chain would see the event otherwise.
            guard viewModel.editingItem == nil, !viewModel.pinboardPopoverShown,
                  !viewModel.creatingItem, viewModel.renamingItem == nil else { return false }
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
            // Bare digit 1-9 (no modifiers) pastes the Nth visible card directly, but
            // only while browsing (query empty) — mirrors the space-preview gate below
            // so it never fights type-to-search. ⌘-digit tab switching is handled above
            // and already returns before reaching this point, so it never collides.
            let allowsDigitQuickPaste = viewModel.query.isEmpty
                && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            let pasteVisible: (Int) -> Void = { index in
                guard viewModel.items.indices.contains(index) else { return }
                viewModel.requestPaste(viewModel.items[index], plain: false)
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
            case 45 where event.modifierFlags.contains(.command)
                && !event.modifierFlags.contains(.shift)
                && !event.modifierFlags.contains(.option): // cmd-N — new item
                viewModel.beginCreate()
                return true
            case 49 where viewModel.query.isEmpty: // space previews in browse mode
                viewModel.previewShown.toggle()
                return true
            case 18 where allowsDigitQuickPaste: // 1
                pasteVisible(0)
                return true
            case 19 where allowsDigitQuickPaste: // 2
                pasteVisible(1)
                return true
            case 20 where allowsDigitQuickPaste: // 3
                pasteVisible(2)
                return true
            case 21 where allowsDigitQuickPaste: // 4
                pasteVisible(3)
                return true
            case 23 where allowsDigitQuickPaste: // 5
                pasteVisible(4)
                return true
            case 22 where allowsDigitQuickPaste: // 6
                pasteVisible(5)
                return true
            case 26 where allowsDigitQuickPaste: // 7
                pasteVisible(6)
                return true
            case 28 where allowsDigitQuickPaste: // 8
                pasteVisible(7)
                return true
            case 25 where allowsDigitQuickPaste: // 9
                pasteVisible(8)
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
        shelfViewModel.onCopyText = { [weak self] text in
            self?.copyText(text)
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
    private lazy var onboardingWindowController = OnboardingWindowController()

    init() throws {
        let database = try DatabaseManager.makeDefault()
        let blobs = BlobStore(directory: database.blobsDirectory)
        let store = ItemStore(writer: database.writer, blobs: blobs)
        self.store = store
        self.pinboardStore = PinboardStore(writer: database.writer)
        self.pasteService = PasteService(pasteboard: NSPasteboard.general,
                                         keyPoster: CGKeyEventPoster())
        let pasteStackModel = PasteStackModel(store: store)
        self.pasteStackModel = pasteStackModel
        let settings = SettingsStore()
        self.settings = settings
        let linkFetcher = LinkMetadataFetcher(store: store)
        let ocrController = OCRController(store: store)
        let reporter = saveErrors
        self.monitor = ClipboardMonitor(
            pasteboard: NSPasteboard.general,
            rules: RulesEngine(excludedBundleIDs: Set(settings.excludedBundleIDs)),
            frontmostApp: {
                let app = NSWorkspace.shared.frontmostApplication
                return (app?.bundleIdentifier, app?.localizedName)
            },
            onCapture: { [persistQueue, linkFetcher, ocrController, settings, pasteStackModel] captured in
                persistQueue.async {
                    do {
                        let saved = try store.save(captured)
                        DispatchQueue.main.async {
                            linkFetcher.fetchIfNeeded(for: saved, enabled: settings.fetchLinkPreviews)
                            ocrController.recognizeIfNeeded(for: saved, enabled: settings.recognizeImageText)
                            // While the stack is active, new copies join the queue too —
                            // "copying while the stack is active" enqueues automatically.
                            if pasteStackModel.isActive {
                                pasteStackModel.enqueue(saved)
                            }
                        }
                    } catch {
                        reporter.report(error)
                    }
                }
            }
        )
        self.linkFetcher = linkFetcher
        self.ocrController = ocrController
        settings.onRulesChange = { [weak self] excludedBundleIDs in
            self?.monitor.rules = RulesEngine(excludedBundleIDs: excludedBundleIDs)
        }
        // `self` is fully initialized past this point, so it's safe to capture weakly
        // in `onActiveChange` — the single fan-out point for palette visibility AND
        // engine activation, so the two can never drift out of lockstep (see the
        // `pasteStackModel` doc comment above).
        pasteStackModel.onActiveChange = { [weak self] isActive in
            guard let self else { return }
            self.pasteStackController.syncVisibility(to: isActive)
            if isActive {
                let tapCreated = self.pasteStackEngine.activate()
                NSLog("Copy: Paste Stack tap \(tapCreated ? "activated" : "could not be created, falling back to hotkey")")
                if !tapCreated {
                    KeyboardShortcuts.enable(.pasteNextFromStack)
                    HUD.show("Use Control Option Command N to paste the next item")
                }
            } else {
                self.pasteStackEngine.deactivate()
                KeyboardShortcuts.disable(.pasteNextFromStack)
            }
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

    /// Shows the first-run welcome flow. `AppDelegate` calls this once at launch,
    /// gated on the `"hasOnboarded"` UserDefaults flag that `OnboardingView.finish()`
    /// sets on its last step.
    func showOnboarding() {
        onboardingWindowController.show()
    }

    /// Refreshes the shelf's live permission state before showing it (not on hide) —
    /// `shelfViewModel`/`shelfController` are both created once and reused for the
    /// app's lifetime, so without this the permission banner would only ever reflect
    /// whatever was true the very first time the shelf ever appeared.
    func toggleShelf() {
        if !shelfController.isVisible {
            shelfViewModel.refreshPermissionState()
        }
        shelfController.toggle()
    }

    /// Opens the shelf (if not already open) and immediately shows `CreateItemSheet`,
    /// for the status menu's "New Item…" action.
    func newItem() {
        if !shelfController.isVisible {
            shelfViewModel.refreshPermissionState()
            shelfController.show()
        }
        shelfViewModel.beginCreate()
    }

    func togglePause() {
        isPaused.toggle()
        monitor.isPaused = isPaused
    }

    func recentItems() -> [ClipItem] {
        (try? store.recentItems(limit: 10)) ?? []
    }

    /// Pastes the single most-recent history item directly into the frontmost app,
    /// without opening the shelf — the global "Quick Paste Latest" hotkey. Reuses
    /// `pasteFromShelf`'s place-reps + accessibility ⌘V path (with its "Press ⌘V"
    /// HUD fallback when Accessibility isn't granted).
    func quickPasteLatest() {
        guard let item = (try? store.recentItems(limit: 1))?.first else {
            HUD.show("Nothing to paste")
            return
        }
        pasteFromShelf(item, plainTextOnly: false)
    }

    /// Advances the shelf's active tab to the next pinboard (History → first pinboard
    /// → ... → wraps back to History) — the global "Next Pinboard" hotkey. If the shelf
    /// isn't open yet, this opens it (landing on History) rather than cycling blind;
    /// the user presses the hotkey again to actually advance once the shelf is visible.
    func selectNextPinboard() {
        guard shelfController.isVisible else {
            shelfViewModel.refreshPermissionState()
            shelfController.show()
            return
        }
        let pinboards = shelfViewModel.pinboards
        switch shelfViewModel.tab {
        case .history:
            if let first = pinboards.first, let id = first.id {
                shelfViewModel.tab = .pinboard(id)
            }
        case .pinboard(let currentID):
            let nextIndex = (pinboards.firstIndex(where: { $0.id == currentID }) ?? -1) + 1
            if pinboards.indices.contains(nextIndex), let id = pinboards[nextIndex].id {
                shelfViewModel.tab = .pinboard(id)
            } else {
                shelfViewModel.tab = .history
            }
        }
    }

    /// Enqueues `item` into the Paste Stack (activating the palette if it wasn't
    /// already) from the card context menu's "Add to Paste Stack" action. The palette
    /// re-fits its own size to the new row via `PasteStackView.onContentChange`, so
    /// there's no need to poke the controller directly here.
    func addToPasteStack(_ item: ClipItem) {
        pasteStackModel.enqueue(item)
        HUD.show("Added to Paste Stack")
    }

    /// Places OCR-recognized text from an image card's "Copy Text" action on the
    /// clipboard (marked self-paste). This is a plain copy, not a paste-in-place — no
    /// keystroke is synthesized, matching `onPasteMultiple`'s "place only" behavior,
    /// since the user asked to copy the text, not paste it.
    func copyText(_ text: String) {
        pasteService.place(
            [CapturedRepresentation(uti: "public.utf8-plain-text", data: Data(text.utf8))],
            plainTextOnly: false)
        HUD.show("Text copied")
    }

    /// Whether the Paste Stack palette/engine are currently active — read by
    /// `AppDelegate` to reflect a checkmark on the "Paste Stack" menu item.
    var isPasteStackActive: Bool { pasteStackModel.isActive }

    /// Flips the Paste Stack on or off. All activation/deactivation — the palette, the
    /// CGEvent tap, and the `.pasteNextFromStack` fallback hotkey — fans out from
    /// `pasteStackModel.isActive`'s `didSet`, wired to `onActiveChange` in `init()`.
    func togglePasteStack() {
        pasteStackModel.isActive.toggle()
    }

    /// Advances the queue and places the next item's representations on the
    /// pasteboard, shared by both the engine-intercepted path and the
    /// `.pasteNextFromStack` fallback hotkey. Returns `false` once the queue is
    /// exhausted, having already deactivated the stack and shown the "finished" HUD.
    @discardableResult
    private func placeNextStackItem() -> Bool {
        guard let reps = pasteStackModel.advanceAndResolve() else {
            deactivatePasteStack()
            HUD.show("Paste Stack finished")
            return false
        }
        pasteService.place(reps, plainTextOnly: false)
        return true
    }

    /// Called by `PasteStackEngine`'s `onIntercept` when the CGEvent tap swallows a
    /// plain ⌘V. This path only runs with Accessibility granted (the tap itself
    /// requires it), so after placing the item it's safe to re-synthesize a marked ⌘V
    /// and have the frontmost app receive it automatically.
    private func pasteNextViaEngine() {
        guard placeNextStackItem() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            PasteStackEngine.postMarkedPasteKeystroke()
        }
    }

    /// `.pasteNextFromStack` fallback hotkey handler — only reachable while the tap
    /// couldn't be created (no Accessibility; see `pasteStackModel.onActiveChange`).
    /// Without Accessibility we can't reliably synthesize a ⌘V ourselves (same reason
    /// `pasteFromShelf`/`onPasteMultiple` gate `sendPasteKeystroke()` behind
    /// `AXIsProcessTrusted()`), so this places the item and lets the user's own ⌘V —
    /// which the OS delivers directly, no synthesis needed — do the actual pasting.
    func pasteNextFromStack() {
        guard placeNextStackItem() else { return }
        HUD.show("Ready to paste. Press Command V.")
    }

    private func deactivatePasteStack() {
        pasteStackModel.isActive = false
    }

    /// Called from `AppDelegate.applicationWillTerminate` so the event tap never
    /// outlives the app process. `pasteStackEngine.deactivate()` is called directly
    /// too, as a defensive no-op, in case the tap was ever active without
    /// `pasteStackModel.isActive` reflecting it.
    func applicationWillTerminate() {
        deactivatePasteStack()
        pasteStackEngine.deactivate()
    }

    func clearHistory() {
        do {
            try store.clearHistory(keepFavorites: true)
        } catch {
            NSLog("Copy: failed to clear history: \(error)")
        }
    }

    /// "Export…" status-menu action — writes the full history and pinboards to a
    /// user-chosen `.json` file via `ArchiveController`.
    func exportHistory() {
        archiveController.exportHistory()
    }

    /// "Import…" status-menu action — restores history and pinboards from a
    /// user-chosen `.json` backup file via `ArchiveController`, deduping by content
    /// hash so re-importing the same file never creates duplicates.
    func importHistory() {
        archiveController.importHistory()
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
