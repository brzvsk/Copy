import AppKit
import CopyCore
import ImageIO
import QuickLookThumbnailing

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    func cached(for item: ClipItem) -> NSImage? {
        cache.object(forKey: item.uuid as NSString)
    }

    /// Drops the cached thumbnail for an item so the next render regenerates it. The
    /// cache is keyed by uuid (stable across edits), so an in-place image change like a
    /// rotate must invalidate here or the card keeps showing the pre-rotation thumbnail.
    func invalidate(for item: ClipItem) {
        cache.removeObject(forKey: item.uuid as NSString)
    }

    /// A Finder-style Quick Look thumbnail of a file at `url` (a PDF's first page, a
    /// document's cover, an image's content), cached by the item's uuid. Falls back to
    /// nil (the caller shows the generic type icon) when Quick Look can't render one.
    func fileThumbnail(for item: ClipItem, url: URL, completion: @escaping (NSImage?) -> Void) {
        if let cached = cached(for: item) {
            completion(cached)
            return
        }
        let uuid = item.uuid
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 400, height: 400), scale: 2,
            representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            var image: NSImage?
            if let cg = rep?.cgImage {
                image = NSImage(cgImage: cg, size: .zero)
            }
            DispatchQueue.main.async {
                if let image { self?.cache.setObject(image, forKey: uuid as NSString) }
                completion(image)
            }
        }
    }

    func thumbnail(for item: ClipItem, store: ItemStore, completion: @escaping (NSImage?) -> Void) {
        if let image = cached(for: item) {
            completion(image)
            return
        }
        guard let id = item.id else {
            completion(nil)
            return
        }
        let uuid = item.uuid
        DispatchQueue.global(qos: .userInitiated).async {
            let reps = (try? store.representations(forItemID: id)) ?? []
            let data = reps.first(where: { $0.uti == "public.png" })?.data
                ?? reps.first(where: { $0.uti == "public.tiff" })?.data
            guard let data,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 400,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary)
            else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let image = NSImage(cgImage: cgImage, size: .zero)
            DispatchQueue.main.async {
                self.cache.setObject(image, forKey: uuid as NSString)
                completion(image)
            }
        }
    }
}
