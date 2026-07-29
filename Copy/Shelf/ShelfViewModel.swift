import AppKit
import CopyCore
import Observation

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

    @ObservationIgnored var onPaste: ((ClipItem, Bool) -> Void)?
    @ObservationIgnored var onPasteMultiple: ((String) -> Void)?
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

    /// Reset search/selection when the shelf closes.
    func clearTransientState() {
        previewShown = false
        selection.reset()
        if !query.isEmpty { query = "" }
    }

    func handleCardClick(_ item: ClipItem, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift) {
            selection.shiftClick(item.uuid, in: items.map(\.uuid))
        } else if modifiers.contains(.command) {
            selection.commandClick(item.uuid)
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
        let joined = picked.map { $0.plainText ?? "" }.joined(separator: "\n")
        onPasteMultiple?(joined)
    }

    func deleteSelection() {
        for item in orderedSelectedItems {
            guard let id = item.id else { continue }
            try? store.delete(itemID: id)
        }
        if !query.isEmpty { refresh() }
    }

    func toggleFavoritePrimary() {
        guard let item = primaryItem, let id = item.id else { return }
        try? store.setFavorite(itemID: id, !item.isFavorite)
        if !query.isEmpty { refresh() }
    }

    func addSelection(toPinboard id: Int64) {
        for item in orderedSelectedItems {
            guard let itemID = item.id else { continue }
            try? pinboardStore.add(itemID: itemID, to: id)
        }
    }

    // MARK: - Per-item actions (context menu)

    func delete(_ item: ClipItem) {
        guard let id = item.id else { return }
        try? store.delete(itemID: id)
        if !query.isEmpty { refresh() }
    }

    func toggleFavorite(_ item: ClipItem) {
        guard let id = item.id else { return }
        try? store.setFavorite(itemID: id, !item.isFavorite)
        if !query.isEmpty { refresh() }
    }

    // MARK: - Pinboard actions passthrough

    func createPinboard(name: String, symbol: String) {
        try? pinboardStore.create(name: name, symbol: symbol)
    }

    func renamePinboard(id: Int64, to name: String) {
        try? pinboardStore.rename(id: id, to: name)
    }

    func setPinboardSymbol(id: Int64, _ symbol: String) {
        try? pinboardStore.setSymbol(id: id, symbol)
    }

    func deletePinboard(id: Int64) {
        try? pinboardStore.delete(id: id)
    }

    func addItem(_ item: ClipItem, toPinboard id: Int64) {
        guard let itemID = item.id else { return }
        try? pinboardStore.add(itemID: itemID, to: id)
    }

    func removeItem(_ item: ClipItem, fromPinboard id: Int64) {
        guard let itemID = item.id else { return }
        try? pinboardStore.remove(itemID: itemID, from: id)
    }

    private func apply(_ new: [ClipItem]) {
        items = new
        let order = items.map(\.uuid)
        selection.prune(existing: Set(order), order: order)
    }

    func dragProvider(for item: ClipItem) -> NSItemProvider {
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
