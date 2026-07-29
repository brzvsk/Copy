import CopyCore
import Foundation

/// Runs on-device OCR (`OCRService`) for freshly-captured image items and persists the
/// result through `ItemStore`, so image cards become searchable and gain a "Copy Text"
/// action. Mirrors `LinkMetadataFetcher`'s in-flight-dedup structure: best-effort,
/// failures are logged and never surfaced, and each item is only ever in flight once.
@MainActor
final class OCRController {
    private let store: ItemStore
    private var inFlight: Set<String> = []

    init(store: ItemStore) {
        self.store = store
    }

    /// Kicks off OCR for `item` if it looks like an image that hasn't been recognized
    /// yet. Safe to call repeatedly (e.g. once per save) — already-recognized,
    /// disabled, non-image, or in-flight items are ignored.
    func recognizeIfNeeded(for item: ClipItem, enabled: Bool) {
        guard enabled,
              item.kind == .image,
              item.recognizedText == nil,
              let itemID = item.id,
              !inFlight.contains(item.uuid)
        else { return }

        let uuid = item.uuid
        inFlight.insert(uuid)
        // Detach from this instance: ItemStore wraps a GRDB DatabaseWriter, which is
        // safe to use from any thread, so the representations read and the eventual
        // write can both happen off-main without hopping back through `self`.
        let store = self.store

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let cleanup: () -> Void = {
                Task { @MainActor in self?.inFlight.remove(uuid) }
            }

            guard let reps = try? store.representations(forItemID: itemID) else {
                cleanup()
                return
            }
            let data = reps.first(where: { $0.uti == "public.png" })?.data
                ?? reps.first(where: { $0.uti == "public.tiff" })?.data
            guard let data else {
                cleanup()
                return
            }

            OCRService.recognizeText(in: data) { text in
                defer { cleanup() }
                guard let text, !text.isEmpty else { return }
                do {
                    try store.setRecognizedText(itemID: itemID, text)
                } catch {
                    NSLog("Copy: failed to persist recognized text: \(error)")
                }
            }
        }
    }
}
