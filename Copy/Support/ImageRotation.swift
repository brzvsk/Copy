import AppKit

enum ImageRotation {
    /// Rotates image bytes 90 degrees and re-encodes as PNG. PNG is lossless (so
    /// repeated rotates don't accumulate JPEG artifacts) and is the format
    /// `ThumbnailCache` reads, so the rotated card thumbnail regenerates cleanly.
    /// Returns nil if the bytes aren't a decodable image.
    static func rotated(_ data: Data, clockwise: Bool) -> Data? {
        guard let image = NSImage(data: data),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0,
              let ctx = CGContext(
                data: nil, width: h, height: w, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        // Draw the source rotated 90 degrees about the new center. A rotate swaps the
        // width and height, which is why the context is sized h by w.
        ctx.translateBy(x: CGFloat(h) / 2, y: CGFloat(w) / 2)
        ctx.rotate(by: clockwise ? -.pi / 2 : .pi / 2)
        ctx.draw(cg, in: CGRect(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2,
                                width: CGFloat(w), height: CGFloat(h)))
        guard let rotated = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: rotated).representation(using: .png, properties: [:])
    }
}
