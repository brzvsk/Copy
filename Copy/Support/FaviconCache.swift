import AppKit
import CopyCore

@MainActor
final class FaviconCache {
    static let shared = FaviconCache()
    private let cache = NSCache<NSString, NSImage>()

    func cached(for item: ClipItem) -> NSImage? {
        cache.object(forKey: cacheKey(for: item.uuid))
    }

    func favicon(for item: ClipItem, store: ItemStore, completion: @escaping (NSImage?) -> Void) {
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
            let data = (try? store.favicon(forItemID: id)) ?? nil
            guard let data, let image = NSImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async {
                self.cache.setObject(image, forKey: self.cacheKey(for: uuid))
                completion(image)
            }
        }
    }

    private func cacheKey(for uuid: String) -> NSString {
        "favicon-\(uuid)" as NSString
    }
}
