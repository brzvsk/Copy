import AppKit
import CopyCore
import Observation

@MainActor
@Observable
final class ShelfViewModel {
    let store: ItemStore

    var items: [ClipItem] = []
    var query = "" {
        didSet { if query != oldValue { refresh() } }
    }
    var scope: ShelfScope = .all {
        didSet { if scope != oldValue { refresh() } }
    }
    var selectedIndex = 0
    var previewShown = false

    @ObservationIgnored var onPaste: ((ClipItem, Bool) -> Void)?
    @ObservationIgnored private var token: ObservationToken?

    init(store: ItemStore) {
        self.store = store
        refresh()
    }

    var selectedItem: ClipItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    func refresh() {
        token?.cancel()
        token = nil
        previewShown = false
        if query.isEmpty {
            token = store.observeRecent(kinds: scope.kinds, limit: 100,
                                        onError: { NSLog("Copy: observation failed: \($0)") },
                                        onChange: { [weak self] in self?.apply($0) })
        } else {
            apply((try? store.search(query, kinds: scope.kinds, limit: 100)) ?? [])
        }
    }

    /// Reset search/selection when the shelf closes.
    func clearTransientState() {
        previewShown = false
        selectedIndex = 0
        if !query.isEmpty { query = "" }
    }

    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = max(0, min(items.count - 1, selectedIndex + delta))
    }

    func requestPaste(_ item: ClipItem, plain: Bool) {
        onPaste?(item, plain)
    }

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

    private func apply(_ new: [ClipItem]) {
        items = new
        selectedIndex = items.isEmpty ? 0 : min(selectedIndex, items.count - 1)
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
