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

    /// Resolves queued uuids to `ClipItem`s, preserving queue order. This is a PURE
    /// read: a uuid that no longer resolves to a stored item (deleted or pruned since
    /// being queued) is simply omitted from the returned array, and `queue` itself is
    /// never mutated here. SwiftUI calls this from view bodies (`PasteStackView`
    /// resolves it once per body evaluation) — mutating observed state (`queue`) while
    /// a body is evaluating is undefined behavior, so stale-uuid cleanup happens only
    /// at explicit event points via `reconcile()`, never as a side effect of reading.
    func items() -> [ClipItem] {
        queue.itemUUIDs.compactMap { try? store.item(uuid: $0) }
    }

    /// Drops any queued uuid that no longer resolves to a stored item. Call this at
    /// explicit event points — never from `items()` — such as `PasteStackController`
    /// showing the palette, so the queue doesn't accumulate orphaned uuids forever.
    func reconcile() {
        for uuid in queue.itemUUIDs where (try? store.item(uuid: uuid)) == nil {
            queue.remove(uuid)
        }
    }

    /// Enqueues `item`, activating the palette if it wasn't already.
    func enqueue(_ item: ClipItem) {
        queue.enqueue(item.uuid)
        if !isActive { isActive = true }
    }

    /// Advances the queue and resolves representations for the next item, skipping
    /// (and retrying) any uuid whose item or representations have gone missing since
    /// being queued. Returns `nil` once the queue is exhausted. Unlike `items()`, this
    /// runs from an explicit event handler (the paste engine, in Task 7), not from a
    /// SwiftUI body — `queue.advance()`'s mutation is safe here.
    func advanceAndResolve() -> [CapturedRepresentation]? {
        while let uuid = queue.advance() {
            guard let id = (try? store.item(uuid: uuid))?.id,
                  let reps = try? store.representations(forItemID: id),
                  !reps.isEmpty else {
                continue
            }
            return reps
        }
        return nil
    }
}
