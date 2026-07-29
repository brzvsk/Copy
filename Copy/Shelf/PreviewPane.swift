import SwiftUI
import CopyCore

struct PreviewPane: View {
    let item: ClipItem
    let store: ItemStore

    private var quickLookURLs: [URL] {
        QuickLookController.fileURLs(for: item, store: store)
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
                    Text(String((item.plainText ?? "").prefix(200_000)))
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
