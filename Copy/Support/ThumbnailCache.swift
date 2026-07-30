import AppKit
import CopyCore
import ImageIO

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
