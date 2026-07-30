import AppKit
import ApplicationServices
import CopyCore
import Observation
import UniformTypeIdentifiers

extension UTType {
    /// Internal drag payload identifying a `ClipItem` by uuid, used for card → tab
    /// filing drags within the shelf. Declared in project.yml's Info.plist properties
    /// (`UTExportedTypeDeclarations`) so the system recognizes it during real
    /// drag-and-drop sessions, not just as an in-process string constant.
    static let copyItem = UTType(exportedAs: "com.tarikbc.copy.item")
}

@MainActor
@Observable
final class ShelfViewModel {
    enum ShelfTab: Equatable {
        case history
        case pinboard(Int64)
    }

    let store: ItemStore
    let pinboardStore: PinboardStore
    /// Held so `ShelfRootView`/`ItemCardView` can read `settings.compactShelf` live —
    /// both this view model and `SettingsStore` are `@Observable`, so a body that reads
    /// `viewModel.settings.compactShelf` re-renders on toggle without any extra
    /// change-hook plumbing (the pattern `AppCoordinator` uses for AppKit-side settings
    /// like `hideDuringScreenSharing` doesn't apply here since this is pure SwiftUI).
    let settings: SettingsStore

    var items: [ClipItem] = []
    var query = "" {
        didSet { if query != oldValue { refresh() } }
    }
    var scope: ShelfScope = .all {
        didSet { if scope != oldValue { refresh() } }
    }
    var tab: ShelfTab = .history {
        didSet { if tab != oldValue { refresh() } }
    }
    var pinboards: [Pinboard] = []
    var selection = ShelfSelection()
    var previewShown = false
    var editingItem: ClipItem?
    var pinboardPopoverShown = false
    var creatingItem = false
    var renamingItem: ClipItem?
    var adjustingColorItem: ClipItem?
    /// Drives the inline, click-to-edit title field on a card (`ItemCardView`) — the
    /// primary rename entry point, distinct from the modal `renamingItem`/
    /// `RenameItemSheet` so `AppCoordinator`'s app-wide key monitor guard can treat an
    /// active inline field exactly like the other sheets (see that guard's doc
    /// comment) without the two states being confused for one another.
    var inlineRenamingItemID: Int64?

    /// Mirror `AppCoordinator.isPaused`/`isPasteStackActive` for the in-drawer menu
    /// (`ShelfHeader`'s ellipsis menu), which needs to show "Pause"/"Resume Monitoring"
    /// and a Paste Stack checkmark that reflect those AppKit-owned coordinator states.
    /// `AppCoordinator` pushes these live whenever the underlying state changes
    /// (`togglePause()`, `pasteStackModel.onActiveChange`), the same fan-out shape as
    /// `onCompactShelfChange` etc. keep `SettingsStore` in sync with AppKit-side state.
    var isPrivacyModeOn = false
    var isPasteStackOn = false

    /// Backs `ShelfRootView`'s permission banner. The shelf panel + its SwiftUI content
    /// are created once and reused for the app's lifetime (see
    /// `AppCoordinator.shelfController`), so this can't just be read in `.onAppear` —
    /// that would only ever reflect whatever was true the very first time the shelf
    /// ever appeared. `AppCoordinator.toggleShelf()` calls `refreshPermissionState()`
    /// right before showing the panel instead, so every open reflects live state.
    var accessibilityTrusted = AXIsProcessTrusted()

    @ObservationIgnored var onPaste: ((ClipItem, Bool) -> Void)?
    @ObservationIgnored var onPasteMultiple: ((String) -> Void)?
    @ObservationIgnored var onAddToPasteStack: ((ClipItem) -> Void)?
    @ObservationIgnored var onCopyText: ((String) -> Void)?
    @ObservationIgnored var onAdjustColorCopy: ((String) -> Void)?

    // MARK: - Drawer-menu actions (ShelfHeader's ellipsis menu)
    //
    // Mirror the status menu's actions so the shelf is fully usable with the menu bar
    // icon hidden. `AppCoordinator` wires these to its existing action methods — the
    // same ones the status menu calls — so there's exactly one implementation of each.
    @ObservationIgnored var onNewItem: (() -> Void)?
    @ObservationIgnored var onTogglePasteStack: (() -> Void)?
    @ObservationIgnored var onTogglePrivacyMode: (() -> Void)?
    @ObservationIgnored var onClearHistory: (() -> Void)?
    @ObservationIgnored var onExportHistory: (() -> Void)?
    @ObservationIgnored var onImportHistory: (() -> Void)?
    @ObservationIgnored var onOpenSettings: (() -> Void)?
    /// Bridged directly from `AppDelegate` (not `AppCoordinator`) — the Sparkle
    /// updater controller is owned by `AppDelegate`, not the coordinator.
    @ObservationIgnored var onCheckForUpdates: (() -> Void)?
    /// Also bridged directly from `AppDelegate`, for symmetry with `onCheckForUpdates`
    /// — `NSApp.terminate` doesn't need coordinator state, but wiring it from the same
    /// place keeps both AppDelegate-owned bridges together.
    @ObservationIgnored var onQuit: (() -> Void)?

    @ObservationIgnored private var token: ObservationToken?
    @ObservationIgnored private var pinboardsToken: ObservationToken?

    init(store: ItemStore, pinboardStore: PinboardStore, settings: SettingsStore) {
        self.store = store
        self.pinboardStore = pinboardStore
        self.settings = settings
        pinboardsToken = pinboardStore.observeAll(
            onError: { NSLog("Copy: pinboard observation failed: \($0)") },
            onChange: { [weak self] in self?.pinboards = $0 })
        refresh()
    }

    var primaryItem: ClipItem? {
        guard let uuid = selection.primary else { return nil }
        return items.first(where: { $0.uuid == uuid })
    }

    func isSelected(_ item: ClipItem) -> Bool {
        selection.selected.contains(item.uuid)
    }

    var orderedSelectedItems: [ClipItem] {
        let ordered = selection.orderedSelection(in: items.map(\.uuid))
        return ordered.compactMap { uuid in items.first(where: { $0.uuid == uuid }) }
    }

    func refresh() {
        token?.cancel()
        token = nil
        previewShown = false
        if !query.isEmpty {
            apply((try? store.search(query, kinds: scope.kinds, limit: 100)) ?? [])
            return
        }
        switch tab {
        case .history:
            token = store.observeRecent(kinds: scope.kinds, limit: 100,
                                        onError: { NSLog("Copy: observation failed: \($0)") },
                                        onChange: { [weak self] in self?.apply($0) })
        case .pinboard(let id):
            token = pinboardStore.observeItems(in: id,
                                               onError: { NSLog("Copy: observation failed: \($0)") },
                                               onChange: { [weak self] in self?.apply($0) })
        }
    }

    /// Reset search/selection when the shelf closes. Anchors selection to the newest
    /// item rather than clearing it, since `show()` doesn't re-run `apply(_:)` on
    /// reopen — leaving the selection empty here would otherwise leave ⏎/Space dead
    /// until the user first pressed an arrow key.
    func clearTransientState() {
        previewShown = false
        if let first = items.first { selection.click(first.uuid) } else { selection.reset() }
        editingItem = nil
        creatingItem = false
        renamingItem = nil
        adjustingColorItem = nil
        inlineRenamingItemID = nil
        if !query.isEmpty { query = "" }
    }

    /// Called by `AppCoordinator.toggleShelf()` right before showing the panel — see
    /// the `accessibilityTrusted` doc comment for why a one-time `.onAppear` read isn't
    /// enough.
    func refreshPermissionState() {
        accessibilityTrusted = AXIsProcessTrusted()
    }

    /// Shift/⌘-click always extend the multi-selection, regardless of
    /// `settings.doubleClickToPaste`. A plain click either selects-and-pastes (today's
    /// behavior) or just selects, leaving the paste to `handleCardDoubleClick`/⏎ — see
    /// that setting's doc comment in `SettingsStore`.
    func handleCardClick(_ item: ClipItem, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift) {
            selection.shiftClick(item.uuid, in: items.map(\.uuid))
        } else if modifiers.contains(.command) {
            selection.commandClick(item.uuid, in: items.map(\.uuid))
        } else {
            selection.click(item.uuid)
            if !settings.doubleClickToPaste {
                requestPaste(item, plain: false)
            }
        }
    }

    /// A no-modifier double-click on a card. This is the paste gesture when
    /// `settings.doubleClickToPaste` is on; with it off, a single click already pastes,
    /// so this just re-selects and re-pastes the same item, which is harmless.
    func handleCardDoubleClick(_ item: ClipItem) {
        // A double-click pastes only as a plain (no-modifier) gesture. When a modifier
        // is held the user is building a multi-selection with command/shift-clicks, so a
        // fast second click on the same card must stay a selection toggle (handled by
        // handleCardClick), never collapse the selection and paste.
        let modifiers = NSEvent.modifierFlags
        guard !modifiers.contains(.command), !modifiers.contains(.shift) else { return }
        selection.click(item.uuid)
        requestPaste(item, plain: false)
    }

    func moveSelection(_ delta: Int) {
        selection.move(delta, in: items.map(\.uuid))
    }

    func requestPaste(_ item: ClipItem, plain: Bool) {
        onPaste?(item, plain)
    }

    func pasteSelection(plain: Bool) {
        let picked = orderedSelectedItems
        if picked.count <= 1 {
            if let item = picked.first ?? primaryItem { requestPaste(item, plain: plain) }
            return
        }
        let filtered = picked.filter { isEditableKind($0.kind) || $0.kind == .color }
        guard !filtered.isEmpty else {
            HUD.show("No text in selection")
            return
        }
        if filtered.count == 1 {
            requestPaste(filtered[0], plain: plain)
            return
        }
        let joined = filtered.map { $0.plainText ?? "" }.joined(separator: "\n")
        onPasteMultiple?(joined)
    }

    func deleteSelection() {
        for item in orderedSelectedItems {
            guard let id = item.id else { continue }
            do {
                try store.delete(itemID: id)
            } catch {
                NSLog("Copy: failed to delete item: \(error)")
                HUD.show("Couldn't complete that")
            }
        }
        if !query.isEmpty { refresh() }
    }

    func toggleFavoritePrimary() {
        guard let item = primaryItem, let id = item.id else { return }
        do {
            try store.setFavorite(itemID: id, !item.isFavorite)
        } catch {
            NSLog("Copy: failed to toggle favorite: \(error)")
            HUD.show("Couldn't complete that")
        }
        if !query.isEmpty { refresh() }
    }

    func addSelection(toPinboard id: Int64) {
        for item in orderedSelectedItems {
            guard let itemID = item.id else { continue }
            do {
                try pinboardStore.add(itemID: itemID, to: id)
            } catch {
                NSLog("Copy: failed to add item to pinboard: \(error)")
                HUD.show("Couldn't complete that")
            }
        }
    }

    // MARK: - Per-item actions (context menu)

    func addToPasteStack(_ item: ClipItem) {
        onAddToPasteStack?(item)
    }

    /// Places `item`'s recognized OCR text on the clipboard, marked as a self-paste —
    /// a plain copy, not a paste-in-place, since the user asked to copy the text, not
    /// paste it. No-ops if the item has no recognized text.
    func copyText(_ item: ClipItem) {
        guard let text = item.recognizedText, !text.isEmpty else { return }
        onCopyText?(text)
    }

    /// Opens the system Quick Look panel for a `.file` item's underlying file(s), read
    /// straight from its `public.file-url` representations. No-ops if none of those
    /// files still exist on disk (e.g. the source was moved or deleted since copying).
    func quickLook(_ item: ClipItem) {
        QuickLookController.shared.preview(QuickLookController.fileURLs(for: item, store: store))
    }

    func delete(_ item: ClipItem) {
        guard let id = item.id else { return }
        do {
            try store.delete(itemID: id)
        } catch {
            NSLog("Copy: failed to delete item: \(error)")
            HUD.show("Couldn't complete that")
        }
        if !query.isEmpty { refresh() }
    }

    func toggleFavorite(_ item: ClipItem) {
        guard let id = item.id else { return }
        do {
            try store.setFavorite(itemID: id, !item.isFavorite)
        } catch {
            NSLog("Copy: failed to toggle favorite: \(error)")
            HUD.show("Couldn't complete that")
        }
        if !query.isEmpty { refresh() }
    }

    // MARK: - Pinboard actions passthrough

    func createPinboard(name: String, symbol: String, emoji: String? = nil, tint: String = "") {
        do {
            try pinboardStore.create(name: name, symbol: symbol, emoji: emoji, tint: tint)
        } catch {
            NSLog("Copy: failed to create pinboard: \(error)")
            HUD.show("Couldn't complete that")
        }
    }

    func renamePinboard(id: Int64, to name: String) {
        do {
            try pinboardStore.rename(id: id, to: name)
        } catch {
            NSLog("Copy: failed to rename pinboard: \(error)")
            HUD.show("Couldn't complete that")
        }
    }

    func setPinboardSymbol(id: Int64, _ symbol: String) {
        do {
            try pinboardStore.setSymbol(id: id, symbol)
        } catch {
            NSLog("Copy: failed to set pinboard symbol: \(error)")
            HUD.show("Couldn't complete that")
        }
    }

    func setPinboardEmoji(id: Int64, _ emoji: String?) {
        do {
            try pinboardStore.setEmoji(id: id, emoji)
        } catch {
            NSLog("Copy: failed to set pinboard emoji: \(error)")
            HUD.show("Couldn't complete that")
        }
    }

    func setPinboardTint(id: Int64, _ tint: String) {
        do {
            try pinboardStore.setTint(id: id, tint)
        } catch {
            NSLog("Copy: failed to set pinboard tint: \(error)")
            HUD.show("Couldn't complete that")
        }
    }

    func deletePinboard(id: Int64) {
        do {
            try pinboardStore.delete(id: id)
            if tab == .pinboard(id) { tab = .history }
        } catch {
            NSLog("Copy: failed to delete pinboard: \(error)")
            HUD.show("Couldn't complete that")
        }
    }

    func addItem(_ item: ClipItem, toPinboard id: Int64) {
        guard let itemID = item.id else { return }
        do {
            try pinboardStore.add(itemID: itemID, to: id)
        } catch {
            NSLog("Copy: failed to add item to pinboard: \(error)")
            HUD.show("Couldn't complete that")
        }
    }

    func removeItem(_ item: ClipItem, fromPinboard id: Int64) {
        guard let itemID = item.id else { return }
        do {
            try pinboardStore.remove(itemID: itemID, from: id)
        } catch {
            NSLog("Copy: failed to remove item from pinboard: \(error)")
            HUD.show("Couldn't complete that")
        }
    }

    /// Looks up an item by uuid for a card→tab drop. `items` only holds the current
    /// tab/search's rows, which may exclude the dragged item (e.g. dropping a History
    /// card onto a different pinboard tab), so this falls back to a broader store scan.
    func item(forUUID uuid: String) -> ClipItem? {
        if let match = items.first(where: { $0.uuid == uuid }) { return match }
        return (try? store.recentItems(limit: 1_000))?.first(where: { $0.uuid == uuid })
    }

    /// Handles a card (or a whole multi-selection) dropped onto a pinboard tab.
    /// `uuids` is one uuid for a single-card drag, or the ordered selection's uuids
    /// for a multi-selection drag (see `ShelfViewModel.multiDragProvider()`).
    func dropItems(uuids: [String], toPinboard pinboard: Pinboard) {
        guard let id = pinboard.id else { return }
        var added = 0
        for uuid in uuids {
            guard let item = item(forUUID: uuid), let itemID = item.id else { continue }
            do {
                try pinboardStore.add(itemID: itemID, to: id)
                added += 1
            } catch {
                NSLog("Copy: failed to add item to pinboard: \(error)")
            }
        }
        switch added {
        case 0: HUD.show("Couldn't complete that")
        case 1: HUD.show("Added to \(pinboard.name)")
        default: HUD.show("Added \(added) items to \(pinboard.name)")
        }
    }

    /// Called from a card's "Edit…" context menu item (with that card's item) and the
    /// ⌘E shortcut (parameterless, targets the primary selection). No-ops for kinds
    /// `EditItemSheet` can't meaningfully edit (mirrors `ItemCardView.isEditable`).
    func beginEdit(_ item: ClipItem? = nil) {
        guard let target = item ?? primaryItem, isEditableKind(target.kind) else { return }
        editingItem = target
    }

    /// Saves edited rich text from `EditItemSheet`, then dismisses it either way. RTF
    /// encoding happens here (the app layer) rather than in CopyCore, which stays
    /// Foundation-only and takes pre-encoded `Data` — see `ItemStore.replaceContent(itemID:rtfData:plainText:)`.
    func commitEdit(attributed: NSAttributedString) {
        defer { editingItem = nil }
        guard let item = editingItem, let id = item.id else { return }
        let plainText = attributed.string
        guard let rtfData = attributed.rtf(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [:]
        ) else {
            NSLog("Copy: failed to RTF-encode edited item")
            HUD.show("Couldn't save changes")
            return
        }
        do {
            try store.replaceContent(itemID: id, rtfData: rtfData, plainText: plainText)
        } catch {
            NSLog("Copy: failed to save edited item: \(error)")
            HUD.show("Couldn't save changes")
        }
    }

    /// Opens `CreateItemSheet` from ⌘N or the status menu's "New Item…" action.
    func beginCreate() {
        creatingItem = true
    }

    /// Creates a user-authored text item from `CreateItemSheet`, then dismisses it
    /// either way.
    func commitCreate(text: String, title: String?) {
        defer { creatingItem = false }
        do {
            try store.createTextItem(text, title: title?.isEmpty == true ? nil : title)
        } catch {
            NSLog("Copy: failed to create item: \(error)")
            HUD.show("Couldn't create item")
        }
    }

    /// Opens `RenameItemSheet` from a card's "Rename…" context menu item, seeded
    /// with `item.title`. No longer wired to any entry point now that rename is
    /// inline-first (see `beginInlineRename(_:)`) — kept, along with `renamingItem`
    /// and `RenameItemSheet` itself, in case a modal path is needed again.
    func beginRename(_ item: ClipItem) {
        renamingItem = item
    }

    /// Saves a new title from `RenameItemSheet`, then dismisses it either way. An
    /// empty title clears the custom title, reverting display to the auto title.
    func commitRename(_ item: ClipItem, to title: String) {
        defer { renamingItem = nil }
        saveTitle(item, to: title)
    }

    /// Begins inline (click-to-edit) rename of `item`'s title in place on its card —
    /// the primary rename entry point (title tap, context-menu "Rename…", and ⌘R all
    /// route here). Distinct from `renamingItem`/`beginRename` so the app-wide key
    /// monitor guard in `AppCoordinator` can gate on this state on its own.
    func beginInlineRename(_ item: ClipItem) {
        inlineRenamingItemID = item.id
    }

    /// Saves a new title from the inline title field, then clears inline-rename state
    /// either way — but only if it still points at `item`. A stale commit can arrive
    /// here after `inlineRenamingItemID` has already moved on to a different card (see
    /// `InlineTitleField`'s `.onDisappear`, which commits the outgoing card's edit
    /// when the user starts renaming a new one before the old one resolved); clearing
    /// unconditionally would stomp the new card's rename session back to nil right
    /// after it started. Same save semantics as `commitRename` (empty title clears
    /// back to the auto title).
    func commitInlineRename(_ item: ClipItem, to title: String) {
        defer { if inlineRenamingItemID == item.id { inlineRenamingItemID = nil } }
        saveTitle(item, to: title)
    }

    /// Cancels an in-progress inline rename without saving (Escape).
    func cancelInlineRename() {
        inlineRenamingItemID = nil
    }

    private func saveTitle(_ item: ClipItem, to title: String) {
        guard let id = item.id else { return }
        do {
            try store.setTitle(itemID: id, title.isEmpty ? nil : title)
        } catch {
            NSLog("Copy: failed to rename item: \(error)")
            HUD.show("Couldn't rename item")
        }
        if !query.isEmpty { refresh() }
    }

    /// Opens `ColorAdjustSheet` from a color card's "Adjust Color…" context menu item,
    /// seeded with the item's current hex. No-ops for non-color items.
    func beginAdjustColor(_ item: ClipItem) {
        guard item.kind == .color else { return }
        adjustingColorItem = item
    }

    /// Places the tweaked color (as a hex string) via the coordinator's
    /// `onAdjustColorCopy` hook, then dismisses the sheet either way. Does not mutate
    /// the stored item — this is a re-copy with a tweak, not an edit.
    func commitAdjustColor(_ hex: String) {
        defer { adjustingColorItem = nil }
        onAdjustColorCopy?(hex)
    }

    private func isEditableKind(_ kind: ItemKind) -> Bool {
        switch kind {
        case .text, .richText, .link: return true
        case .image, .file, .color: return false
        }
    }

    private func apply(_ new: [ClipItem]) {
        items = new
        let order = items.map(\.uuid)
        selection.prune(existing: Set(order), order: order)
        if selection.selected.isEmpty, let first = items.first { selection.click(first.uuid) }
    }

    /// Builds the drag payload for a card: its native representations (so dragging out
    /// to other apps still works) plus an internal uuid representation (so dropping on
    /// a pinboard tab can resolve it back to a `ClipItem` via `item(forUUID:)`).
    ///
    /// When the dragged card is part of a multi-selection (more than one card
    /// selected), the WHOLE ordered selection drags together instead of just this
    /// card — see `multiDragProvider()`. Dragging a card that ISN'T in the current
    /// selection (or when only one card is selected) keeps today's single-item
    /// behavior unchanged.
    func dragProvider(for item: ClipItem) -> NSItemProvider {
        if selection.selected.contains(item.uuid), selection.selected.count > 1 {
            return multiDragProvider()
        }
        let provider = contentProvider(for: item)
        let uuid = item.uuid
        provider.registerDataRepresentation(forTypeIdentifier: UTType.copyItem.identifier, visibility: .all) { completion in
            completion(Data(uuid.utf8), nil)
            return nil
        }
        return provider
    }

    /// One `NSItemProvider` for the whole ordered selection. SwiftUI's `.onDrag(_:)`
    /// returns exactly one `NSItemProvider` on macOS 14 — there's no multi-provider
    /// drag session until later SDKs, and a true per-item multi-drag would mean
    /// replacing this whole drag path (and the pinboard-filing drop it feeds) with an
    /// AppKit `NSDraggingSession`/`NSDraggingSource` rework. The pragmatic,
    /// macOS-14-safe answer: one provider whose text representation is every selected
    /// item's plain text, newline-joined in visible order, so dropping it into any
    /// text-accepting app (TextEdit, a browser field, Notes...) drops all selected
    /// items together. It also carries every selected uuid (newline-joined) under the
    /// internal `copyItem` type, so dropping the whole selection onto a pinboard tab
    /// files all of them — see `ShelfRootView`'s pinboard `.onDrop` and `dropItems(uuids:toPinboard:)`.
    private func multiDragProvider() -> NSItemProvider {
        let selected = orderedSelectedItems
        let joinedText = selected.map { $0.plainText ?? "" }.joined(separator: "\n")
        let provider = NSItemProvider(object: joinedText as NSString)
        let uuids = selected.map(\.uuid).joined(separator: "\n")
        provider.registerDataRepresentation(forTypeIdentifier: UTType.copyItem.identifier, visibility: .all) { completion in
            completion(Data(uuids.utf8), nil)
            return nil
        }
        return provider
    }

    private func contentProvider(for item: ClipItem) -> NSItemProvider {
        guard let id = item.id, let reps = try? store.representations(forItemID: id) else {
            return NSItemProvider()
        }
        if let urlRep = reps.first(where: { $0.uti == "public.file-url" }),
           let url = URL(dataRepresentation: urlRep.data, relativeTo: nil) {
            return NSItemProvider(object: url as NSURL)
        }
        if item.kind == .image,
           let rep = reps.first(where: { $0.uti == "public.png" }) ?? reps.first(where: { $0.uti == "public.tiff" }) {
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: rep.uti, visibility: .all) { completion in
                completion(rep.data, nil)
                return nil
            }
            return provider
        }
        if item.kind == .link, let url = URL(string: item.plainText ?? "") {
            return NSItemProvider(object: url as NSURL)
        }
        return NSItemProvider(object: (item.plainText ?? "") as NSString)
    }
}
