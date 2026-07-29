import AppKit
import CopyCore
import LinkPresentation

/// Fetches a title and favicon for freshly-captured link items via `LinkPresentation`,
/// then persists them through `ItemStore` so the shelf's link cards can show real
/// metadata instead of a bare URL. Fetches are best-effort: failures are logged and
/// never surfaced to the user, and each item is only ever in flight once.
@MainActor
final class LinkMetadataFetcher {
    private let store: ItemStore
    private var inFlight: Set<String> = []
    /// Keeps each in-flight `LPMetadataProvider` alive until its completion handler
    /// fires. `LPMetadataProvider` does not retain itself, so a bare local would be
    /// deallocated (silently cancelling the fetch) as soon as `fetchIfNeeded` returns.
    private var activeProviders: [String: LPMetadataProvider] = [:]

    init(store: ItemStore) {
        self.store = store
    }

    /// Kicks off a metadata fetch for `item` if it looks like a link that hasn't been
    /// resolved yet. Safe to call repeatedly (e.g. once per save) — already-resolved,
    /// disabled, or in-flight items are ignored.
    func fetchIfNeeded(for item: ClipItem, enabled: Bool) {
        guard enabled,
              item.kind == .link,
              item.linkTitle == nil,
              let itemID = item.id,
              let urlString = item.plainText,
              let url = URL(string: urlString),
              !inFlight.contains(item.uuid)
        else { return }

        let uuid = item.uuid
        inFlight.insert(uuid)
        // Detach from the coordinator's LinkMetadataFetcher instance: ItemStore wraps a
        // GRDB DatabaseWriter, which is safe to use from any thread, so the completion
        // handler (delivered on an arbitrary queue) can write through this local copy
        // without hopping back to the main actor.
        let store = self.store

        let provider = LPMetadataProvider()
        activeProviders[uuid] = provider

        provider.startFetchingMetadata(for: url) { [weak self] metadata, error in
            let cleanup: () -> Void = {
                Task { @MainActor in
                    self?.inFlight.remove(uuid)
                    self?.activeProviders.removeValue(forKey: uuid)
                }
            }

            guard let metadata, error == nil else {
                if let error {
                    NSLog("Copy: link metadata fetch failed for \(url.absoluteString): \(error)")
                }
                cleanup()
                return
            }

            // The title's write triggers the shelf's live ValueObservation and mounts
            // the favicon view, so the icon must land in the database first — otherwise
            // the card's one-shot favicon lookup fires before the favicon exists and
            // the icon doesn't show until the shelf is reopened. Icon failure or
            // absence must never block the title, so this always runs last.
            func persistTitle() {
                if let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                    do {
                        try store.setLinkTitle(itemID: itemID, title)
                    } catch {
                        NSLog("Copy: failed to persist link title: \(error)")
                    }
                }
                cleanup()
            }

            guard let iconProvider = metadata.iconProvider else {
                persistTitle()
                return
            }

            iconProvider.loadObject(ofClass: NSImage.self) { image, error in
                if let image = image as? NSImage,
                   let pngData = Self.downscaledPNG(from: image, maxDimension: 64) {
                    do {
                        try store.setFavicon(itemID: itemID, pngData: pngData)
                    } catch {
                        NSLog("Copy: failed to persist favicon: \(error)")
                    }
                } else {
                    NSLog("Copy: favicon load failed for \(url.absoluteString): "
                        + (error?.localizedDescription ?? "no image data"))
                }
                persistTitle()
            }
        }
    }

    /// Renders `image` into a PNG no larger than `maxDimension` on its longest side.
    /// Runs off the main actor (called from the icon provider's completion handler on
    /// an arbitrary queue), so it must not touch any main-actor state.
    private nonisolated static func downscaledPNG(from image: NSImage, maxDimension: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let scale = min(1, maxDimension / max(size.width, size.height))
        let targetSize = NSSize(width: max(1, size.width * scale), height: max(1, size.height * scale))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = targetSize

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .sourceOver,
                   fraction: 1)

        return rep.representation(using: .png, properties: [:])
    }
}
