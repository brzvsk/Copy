import CopyCore
import Observation

/// Backs the Paste Stack palette (`PasteStackController`/`PasteStackView`): owns the
/// pure `PasteStackQueue` plus whether the palette is currently active, and resolves
/// queued uuids to `ClipItem`s/representations via the store.
@MainActor
@Observable
final class PasteStackModel {
    var queue = PasteStackQueue()

    /// Whether the palette should be on screen. This is the single source of truth for
    /// palette visibility: every code path that wants to show or hide the palette does
    /// it by setting this property, never by calling the controller directly.
    /// `AppCoordinator` wires `onActiveChange` to `PasteStackController.syncVisibility(to:)`,
    /// so the `didSet` below is the one place that decision fans out from.
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            onActiveChange?(isActive)
        }
    }

    let store: ItemStore

    @ObservationIgnored var onActiveChange: ((Bool) -> Void)?

    init(store: ItemStore) {
        self.store = store
    }

    /// Resolves queued uuids to `ClipItem`s, preserving queue order. A uuid that no
    /// longer resolves to a stored item (deleted or pruned since being queued) is
    /// dropped from the queue as a side effect, so the palette never shows a stale row.
    func items() -> [ClipItem] {
        let lookup = itemLookup()
        var resolved: [ClipItem] = []
        for uuid in queue.itemUUIDs {
            if let item = lookup[uuid] {
                resolved.append(item)
            } else {
                queue.remove(uuid)
            }
        }
        return resolved
    }

    /// Enqueues `item`, activating the palette if it wasn't already.
    func enqueue(_ item: ClipItem) {
        queue.enqueue(item.uuid)
        if !isActive { isActive = true }
    }

    /// Advances the queue and resolves representations for the next item, skipping
    /// (and retrying) any uuid whose item or representations have gone missing since
    /// being queued. Returns `nil` once the queue is exhausted.
    func advanceAndResolve() -> [CapturedRepresentation]? {
        let lookup = itemLookup()
        while let uuid = queue.advance() {
            guard let id = lookup[uuid]?.id,
                  let reps = try? store.representations(forItemID: id),
                  !reps.isEmpty else {
                continue
            }
            return reps
        }
        return nil
    }

    private func itemLookup() -> [String: ClipItem] {
        let all = (try? store.recentItems(limit: 1_000)) ?? []
        return all.reduce(into: [String: ClipItem]()) { $0[$1.uuid] = $1 }
    }
}
