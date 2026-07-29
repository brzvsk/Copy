import SwiftUI
import CopyCore

struct PreviewPane: View {
    let item: ClipItem
    let store: ItemStore

    private var quickLookURLs: [URL] {
        QuickLookController.fileURLs(for: item, store: store)
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
    /// Any remainder past the highlighted portion still renders, just as plain mono
    /// text, exactly as the whole thing did before this feature existed.
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
                CardThumbnail(item: item, store: store)
                    .padding(12)
            case .color:
                VStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Tokens.color(fromHex: item.plainText ?? ""))
                    Text(item.plainText ?? "")
                        .font(.system(size: 15, design: .monospaced))
                }
                .padding(16)
            case .file:
                VStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(for: Tokens.fileType(for: item)))
                        .resizable()
                        .frame(width: 64, height: 64)
                    Text(item.plainText ?? "File")
                        .font(.system(size: 13, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                    if !quickLookURLs.isEmpty {
                        Button("Quick Look") {
                            QuickLookController.shared.preview(quickLookURLs)
                        }
                    }
                }
                .padding(16)
            default:
                ScrollView {
                    codeAwarePreviewText(item.plainText ?? "")
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(14)
                }
            }
        }
        .frame(width: 420, height: 320)
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
