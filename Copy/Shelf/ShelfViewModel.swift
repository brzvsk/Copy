import AppKit
import ApplicationServices
import CopyCore
import Observation
import UniformTypeIdentifiers

extension UTType {
    /// Internal drag payload identifying a `ClipItem` by uuid, used for card → tab
    /// filing drags within the shelf. `exportedAs` avoids needing an Info.plist
    /// declaration since only this app produces and consumes the type.
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
    @ObservationIgnored private var token: ObservationToken?
    @ObservationIgnored private var pinboardsToken: ObservationToken?

    init(store: ItemStore, pinboardStore: PinboardStore) {
        self.store = store
        self.pinboardStore = pinboardStore
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
        if !query.isEmpty { query = "" }
    }

    /// Called by `AppCoordinator.toggleShelf()` right before showing the panel — see
    /// the `accessibilityTrusted` doc comment for why a one-time `.onAppear` read isn't
    /// enough.
    func refreshPermissionState() {
        accessibilityTrusted = AXIsProcessTrusted()
    }

    func handleCardClick(_ item: ClipItem, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift) {
            selection.shiftClick(item.uuid, in: items.map(\.uuid))
        } else if modifiers.contains(.command) {
            selection.commandClick(item.uuid, in: items.map(\.uuid))
        } else {
            selection.click(item.uuid)
            requestPaste(item, plain: false)
        }
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

    func createPinboard(name: String, symbol: String) {
        do {
            try pinboardStore.create(name: name, symbol: symbol)
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

    /// Handles a card dropped onto a pinboard tab.
    func dropItem(uuid: String, toPinboard pinboard: Pinboard) {
        guard let id = pinboard.id, let item = item(forUUID: uuid), let itemID = item.id else { return }
        do {
            try pinboardStore.add(itemID: itemID, to: id)
            HUD.show("Added to \(pinboard.name)")
        } catch {
            NSLog("Copy: failed to add item to pinboard: \(error)")
            HUD.show("Couldn't complete that")
        }
    }

    /// Called from a card's "Edit…" context menu item (with that card's item) and the
    /// ⌘E shortcut (parameterless, targets the primary selection). No-ops for kinds
    /// `EditItemSheet` can't meaningfully edit (mirrors `ItemCardView.isEditable`).
    func beginEdit(_ item: ClipItem? = nil) {
        guard let target = item ?? primaryItem, isEditableKind(target.kind) else { return }
        editingItem = target
    }

    /// Saves edited text from `EditItemSheet`, then dismisses it either way.
    func commitEdit(_ text: String) {
        defer { editingItem = nil }
        guard let item = editingItem, let id = item.id else { return }
        do {
            try store.replaceContent(itemID: id, with: text)
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
    /// with `item.title`.
    func beginRename(_ item: ClipItem) {
        renamingItem = item
    }

    /// Saves a new title from `RenameItemSheet`, then dismisses it either way. An
    /// empty title clears the custom title, reverting display to the auto title.
    func commitRename(_ item: ClipItem, to title: String) {
        defer { renamingItem = nil }
        guard let id = item.id else { return }
        do {
            try store.setTitle(itemID: id, title.isEmpty ? nil : title)
        } catch {
            NSLog("Copy: failed to rename item: \(error)")
            HUD.show("Couldn't rename item")
        }
        if !query.isEmpty { refresh() }
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
    func dragProvider(for item: ClipItem) -> NSItemProvider {
        let provider = contentProvider(for: item)
        let uuid = item.uuid
        provider.registerDataRepresentation(forTypeIdentifier: UTType.copyItem.identifier, visibility: .all) { completion in
            completion(Data(uuid.utf8), nil)
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
