import SwiftUI
import CopyCore
import ImageIO
import UniformTypeIdentifiers

struct PreviewPane: View {
    let item: ClipItem
    let store: ItemStore
    @State private var imagePixelSize: CGSize?

    private static let imagePadding: CGFloat = 12
    private static let fallbackImagePixelSize = CGSize(width: 1_200, height: 900)

    init(item: ClipItem, store: ItemStore) {
        self.item = item
        self.store = store
        // The visible card has normally populated this cache already. Seeding from it
        // lets the popover open at the right aspect ratio immediately; the preview
        // decoder replaces it with the original pixel dimensions once metadata loads.
        _imagePixelSize = State(initialValue: ThumbnailCache.shared.cached(for: item)?.size)
    }

    private var quickLookURLs: [URL] {
        QuickLookController.fileURLs(for: item, store: store)
    }

    /// File cards keep their original on-disk URLs instead of image bytes in Copy's
    /// database. When the first available file is itself an image, route Space preview
    /// through an image renderer rather than treating it like a generic document.
    private var imageFileURL: URL? {
        quickLookURLs.first { url in
            guard let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
                  let contentType = values.contentType else { return false }
            return contentType.conforms(to: .image)
        }
    }

    private var screen: NSScreen? {
        NSApp.keyWindow?.screen ?? NSScreen.main
    }

    /// Size of the popover's actual content surface. Image previews retain their source
    /// aspect ratio and use substantially more of the display, while text previews grow
    /// only as tall as their estimated wrapped line count before becoming scrollable.
    private var previewSize: CGSize {
        if item.kind == .image || imageFileURL != nil {
            return imagePreviewSize(for: imagePixelSize ?? Self.fallbackImagePixelSize)
        }
        switch item.kind {
        case .text, .richText, .link:
            return textPreviewSize(for: item.plainText ?? "")
        case .color, .file, .image:
            return CGSize(width: 420, height: 320)
        }
    }

    /// Treat captured pixels as Retina pixels when choosing a natural starting size,
    /// then scale up only very small images and scale down anything beyond the display
    /// cap. The final fit never distorts the source aspect ratio.
    private func imagePreviewSize(for pixelSize: CGSize) -> CGSize {
        let screenSize = screen?.visibleFrame.size ?? CGSize(width: 1_440, height: 900)
        let backingScale = screen?.backingScaleFactor ?? 2
        let maxOuter = CGSize(width: min(1_120, screenSize.width * 0.78),
                              height: min(720, screenSize.height * 0.72))
        let maxContent = CGSize(width: maxOuter.width - Self.imagePadding * 2,
                                height: maxOuter.height - Self.imagePadding * 2)

        let safeWidth = max(pixelSize.width, 1)
        let safeHeight = max(pixelSize.height, 1)
        var content = CGSize(width: safeWidth / backingScale,
                             height: safeHeight / backingScale)

        let minimumLongEdge: CGFloat = 520
        let longEdge = max(content.width, content.height)
        if longEdge < minimumLongEdge {
            let scale = minimumLongEdge / longEdge
            content.width *= scale
            content.height *= scale
        }

        let fitScale = min(1, min(maxContent.width / content.width,
                                  maxContent.height / content.height))
        content.width *= fitScale
        content.height *= fitScale

        return CGSize(width: ceil(content.width + Self.imagePadding * 2),
                      height: ceil(content.height + Self.imagePadding * 2))
    }

    private func textPreviewSize(for text: String) -> CGSize {
        let screenSize = screen?.visibleFrame.size ?? CGSize(width: 1_440, height: 900)
        let minimumWidth: CGFloat = 320
        let maximumWidth = min(520, screenSize.width * 0.55)
        let horizontalPadding: CGFloat = 28
        let averageGlyphWidth: CGFloat = 7.2
        let sourceLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let longestLine = sourceLines.map(\.count).max() ?? 0
        let width = min(maximumWidth,
                        max(minimumWidth, CGFloat(longestLine) * averageGlyphWidth + horizontalPadding))
        let charactersPerLine = max(1, Int((width - horizontalPadding) / averageGlyphWidth))
        let wrappedLines = sourceLines.reduce(0) { count, line in
            count + max(1, Int(ceil(Double(line.count) / Double(charactersPerLine))))
        }
        let minimumHeight: CGFloat = 120
        let maximumHeight = min(620, screenSize.height * 0.62)
        let estimatedHeight = CGFloat(wrappedLines) * 18 + 28
        return CGSize(width: ceil(width),
                      height: ceil(min(maximumHeight, max(minimumHeight, estimatedHeight))))
    }

    /// How much of the preview's text ever gets tokenized for syntax color. The pane
    /// only shows a 420×320 window (a few dozen visible lines), so 10k characters is
    /// comfortably more than anything on screen for realistic pastes; a 500KB code
    /// paste stays instant because tokenization work is bounded by this cap, not by
    /// the paste's actual size. Anything beyond the cap still renders (up to the
    /// existing 200k display cap below), just without color.
    private let highlightCap = 10_000

    /// Builds the default-branch preview text: the same 200k-character display cap as
    /// before, with syntax colors applied to only the first `highlightCap` characters
    /// of that (detection + tokenization are cached per item by `CodeHighlightCache`).
    /// Any remainder past the highlighted portion still renders as plain system text,
    /// exactly as the whole thing did before this feature existed.
    private func codeAwarePreviewText(_ text: String) -> Text {
        let displayText = String(text.prefix(200_000))
        let cap = min(displayText.count, highlightCap)
        let highlightPortion = String(displayText.prefix(cap))
        let highlight = CodeHighlightCache.shared.result(for: text, uuid: item.uuid, cap: cap)
        guard highlight.language != nil else { return Text(displayText) }

        guard displayText.count > highlightPortion.count else {
            return highlightedText(highlightPortion, tokens: highlight.tokens)
        }
        let remainder = String(displayText.dropFirst(highlightPortion.count))
        return highlightedText(highlightPortion, tokens: highlight.tokens) + Text(remainder)
    }

    var body: some View {
        Group {
            switch item.kind {
            case .image:
                StoredImagePreview(item: item, store: store) { imagePixelSize = $0 }
                    .padding(Self.imagePadding)
            case .color:
                VStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Tokens.color(fromHex: item.plainText ?? ""))
                    Text(item.plainText ?? "")
                        .font(.system(size: 15))
                }
                .padding(16)
            case .file:
                if let imageFileURL {
                    FileImagePreview(url: imageFileURL) { imagePixelSize = $0 }
                        .id(imageFileURL)
                        .padding(Self.imagePadding)
                } else {
                    VStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(for: Tokens.fileType(for: item)))
                            .resizable()
                            .frame(width: 64, height: 64)
                        Text(item.plainText ?? "File")
                            .font(.system(size: 13))
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                        if !quickLookURLs.isEmpty {
                            Button("Quick Look") {
                                QuickLookController.shared.preview(quickLookURLs)
                            }
                        }
                    }
                    .padding(16)
                }
            default:
                ScrollView {
                    codeAwarePreviewText(item.plainText ?? "")
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(14)
                }
            }
        }
        .frame(width: previewSize.width, height: previewSize.height)
        .animation(.easeOut(duration: 0.18), value: previewSize)
        // M7: the popover's own chrome is otherwise unstyled (SwiftUI/AppKit gives it
        // a plain system background), so this is a clean single-surface adoption —
        // glass on 26 with Reduce Transparency off, the app's existing `.hudWindow`
        // material otherwise. `clipShape` mirrors `PasteStackView`'s treatment so the
        // `ScrollView` text case (the `default` branch above) doesn't bleed square
        // corners past the rounded backing on either code path.
        .glassSurface(cornerRadius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Decodes a clipboard-backed image at preview resolution rather than scaling the
/// shelf's 400-pixel thumbnail into a large popover. Metadata is read before decoding
/// so the parent can size the popover from the original, orientation-corrected pixels.
private struct StoredImagePreview: View {
    let item: ClipItem
    let store: ItemStore
    let onPixelSize: (CGSize) -> Void
    @State private var image: NSImage?
    @State private var didFail = false
    @State private var didStart = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if didFail {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear(perform: loadImage)
    }

    private func loadImage() {
        guard !didStart, let id = item.id else {
            if item.id == nil { didFail = true }
            return
        }
        didStart = true
        DispatchQueue.global(qos: .userInitiated).async {
            let reps = (try? store.representations(forItemID: id)) ?? []
            let data = reps.first(where: { $0.uti == "public.png" })?.data
                ?? reps.first(where: { $0.uti == "public.tiff" })?.data
            let source = data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
            let pixelSize = source.flatMap(PreviewImageDecoder.orientedPixelSize)
            let cgImage = source.flatMap(PreviewImageDecoder.previewImage)
            let decoded = cgImage.map { NSImage(cgImage: $0, size: .zero) }
            DispatchQueue.main.async {
                if let pixelSize { onPixelSize(pixelSize) }
                image = decoded
                didFail = decoded == nil
            }
        }
    }
}

/// Decodes an image-file card from its original URL for the larger Space preview.
/// This deliberately does not use the 400-point Quick Look thumbnail used by shelf
/// cards: ImageIO downsamples the source itself at a size suitable for a Retina pane.
private struct FileImagePreview: View {
    let url: URL
    let onPixelSize: (CGSize) -> Void
    @State private var image: NSImage?
    @State private var didFail = false
    @State private var didStart = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if didFail {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear(perform: loadImage)
    }

    private func loadImage() {
        guard !didStart else { return }
        didStart = true
        let requestedURL = url
        DispatchQueue.global(qos: .userInitiated).async {
            let source = CGImageSourceCreateWithURL(requestedURL as CFURL, nil)
            let pixelSize = source.flatMap(PreviewImageDecoder.orientedPixelSize)
            let cgImage = source.flatMap(PreviewImageDecoder.previewImage)
            let decoded = cgImage.map { NSImage(cgImage: $0, size: .zero) }
            DispatchQueue.main.async {
                if let pixelSize { onPixelSize(pixelSize) }
                image = decoded
                didFail = decoded == nil
            }
        }
    }
}

private enum PreviewImageDecoder {
    static func orientedPixelSize(_ source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if (5...8).contains(orientation) {
            return CGSize(width: height.doubleValue, height: width.doubleValue)
        }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    static func previewImage(_ source: CGImageSource) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_400,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    }
}
