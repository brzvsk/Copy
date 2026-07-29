import SwiftUI
import CopyCore

struct ItemCardView: View {
    let item: ClipItem
    let isSelected: Bool
    let store: ItemStore
    let pinboards: [Pinboard]
    let currentPinboardID: Int64?
    /// Compact shelf mode (`SettingsStore.compactShelf`, threaded from `ShelfRootView`):
    /// smaller card frame + tighter line limits so more cards fit on screen at once.
    var compact: Bool = false
    let doubleClickToPaste: Bool
    let onClick: (NSEvent.ModifierFlags) -> Void
    let onDoubleClick: () -> Void
    let onPaste: () -> Void
    let onPastePlain: () -> Void
    let onEdit: () -> Void
    let onAdjustColor: () -> Void
    let onRename: () -> Void
    let onToggleFavorite: () -> Void
    let onAddToPinboard: (Int64) -> Void
    let onRemoveFromPinboard: () -> Void
    let onAddToPasteStack: () -> Void
    let onCopyText: () -> Void
    let onQuickLook: () -> Void
    let onDelete: () -> Void
    let dragProvider: () -> NSItemProvider

    private var isEditable: Bool {
        switch item.kind {
        case .text, .richText, .link: return true
        case .image, .file, .color: return false
        }
    }

    /// File URL(s) still on disk for this item, used to gate the "Quick Look" menu
    /// item — see `QuickLookController.fileURLs(for:store:)`.
    private var quickLookURLs: [URL] {
        QuickLookController.fileURLs(for: item, store: store)
    }

    /// Whether the card shows the user-assigned `item.title` row above the body. When
    /// true, `bodyLineLimit(standard:compact:)` trims one line off the body's limit in
    /// both layout modes, since that row eats into the same fixed-height card without
    /// shrinking anything else.
    private var hasCustomTitle: Bool {
        guard let title = item.title else { return false }
        return !title.isEmpty
    }

    /// Resolves a kind's body line limit for the current layout mode, then trims it by
    /// one when a custom title row is showing (see `hasCustomTitle`) so the body never
    /// clips against the card's fixed height.
    private func bodyLineLimit(standard: Int, compact compactValue: Int) -> Int {
        let limit = compact ? compactValue : standard
        return hasCustomTitle ? max(limit - 1, 1) : limit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            header
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.6))
                .frame(height: 1)
            if let title = item.title, !title.isEmpty {
                Text(title)
                    .font(Tokens.cardSubtitle)
                    .lineLimit(1)
            }
            body(for: item.kind)
            Spacer(minLength: 0)
            footer
        }
        .padding(compact ? 8 : 10)
        .frame(width: Tokens.cardWidth(compact: compact), height: Tokens.cardHeight(compact: compact), alignment: .topLeading)
        // M7: deliberately NOT routed through `glassSurface` even on macOS 26. Cards
        // are dense, content-bearing surfaces (up to 11 lines of mono-spaced clipboard
        // text) shown many-at-a-time in a scrolling row — exactly the case Apple's
        // Liquid Glass guidance calls out as the wrong fit ("glass is for the controls
        // and navigation that float above content, not for the content itself"). The
        // shelf panel behind the row is already glass on 26 (`ShelfRootView`); stacking
        // another translucent layer under small text-heavy cards would fight the mono
        // body text's legibility and read as busy rather than intentional. Cards keep
        // `controlBackgroundColor` on every macOS version.
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                if isSelected {
                    RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isSelected ? 2 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow)
                    .padding(6)
                    .accessibilityLabel("Favorite")
            }
        }
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .contextMenu {
            Button("Paste", action: onPaste)
            Button("Paste as Plain Text", action: onPastePlain)
            if item.recognizedText?.isEmpty == false {
                Button("Copy Text", action: onCopyText)
            }
            if item.kind == .file, !quickLookURLs.isEmpty {
                Button("Quick Look", action: onQuickLook)
            }
            Divider()
            if isEditable {
                Button("Edit…", action: onEdit)
                    .keyboardShortcut("e", modifiers: .command)
            } else if item.kind == .color {
                Button("Adjust Color…", action: onAdjustColor)
            }
            Button("Rename…", action: onRename)
            Button(item.isFavorite ? "Unfavorite" : "Favorite", action: onToggleFavorite)
            Menu("Add to Pinboard") {
                if pinboards.isEmpty {
                    Text("No Pinboards")
                } else {
                    ForEach(pinboards, id: \.id) { pinboard in
                        Button {
                            if let id = pinboard.id { onAddToPinboard(id) }
                        } label: {
                            Label(pinboard.name, systemImage: pinboard.symbol)
                        }
                    }
                }
            }
            Button("Add to Paste Stack", action: onAddToPasteStack)
            if currentPinboardID != nil {
                Button("Remove from Pinboard", action: onRemoveFromPinboard)
            }
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
        .onDrag(dragProvider)
        .modifier(CardClickGesture(doubleClickToPaste: doubleClickToPaste,
                                   onClick: onClick, onDoubleClick: onDoubleClick))
    }

    private var header: some View {
        HStack(spacing: 5) {
            if let icon = AppIconCache.icon(forBundleID: item.appBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text(item.appName ?? "Unknown")
                .font(Tokens.cardTitle)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(Tokens.relativeFormatter.localizedString(for: item.lastUsedAt, relativeTo: Date()))
                .font(Tokens.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Renders `text` (capped to `cap` characters, same as the plain-text path always
    /// did) with syntax colors when `CodeDetector` recognizes it as code, otherwise as
    /// plain `Text` exactly as before this feature existed. Detection + tokenization
    /// are cached per item (`CodeHighlightCache`) so scrolling the shelf doesn't
    /// re-run them every frame; "Copy"/paste are untouched — this only changes what's
    /// drawn on screen.
    @ViewBuilder
    private func codeAwareBody(text: String, cap: Int) -> some View {
        let capped = String(text.prefix(cap))
        let highlight = CodeHighlightCache.shared.result(for: text, uuid: item.uuid, cap: cap)
        if highlight.language != nil {
            highlightedText(capped, tokens: highlight.tokens)
        } else {
            Text(capped)
        }
    }

    @ViewBuilder
    private func body(for kind: ItemKind) -> some View {
        switch kind {
        case .text, .richText:
            codeAwareBody(text: item.plainText ?? "", cap: 1_500)
                .font(Tokens.bodyMono)
                .lineLimit(bodyLineLimit(standard: 11, compact: 6))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        case .link:
            if let linkTitle = item.linkTitle {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        LinkFaviconView(item: item, store: store)
                        Text(URL(string: item.plainText ?? "")?.host ?? "Link")
                            .font(Tokens.cardSubtitle)
                            .lineLimit(1)
                    }
                    Text(linkTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(bodyLineLimit(standard: 2, compact: 1))
                        .multilineTextAlignment(.leading)
                    Text(String((item.plainText ?? "").prefix(1_500)))
                        .font(Tokens.bodyMono)
                        .foregroundStyle(.secondary)
                        .lineLimit(bodyLineLimit(standard: 2, compact: 1))
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text(URL(string: item.plainText ?? "")?.host ?? "Link")
                        .font(Tokens.cardSubtitle)
                        .lineLimit(1)
                    Text(String((item.plainText ?? "").prefix(1_500)))
                        .font(Tokens.bodyMono)
                        .foregroundStyle(.secondary)
                        .lineLimit(bodyLineLimit(standard: 5, compact: 3))
                }
            }
        case .image:
            CardThumbnail(item: item, store: store)
        case .file:
            VStack(alignment: .leading, spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(for: Tokens.fileType(for: item)))
                    .resizable()
                    .frame(width: compact ? 32 : 44, height: compact ? 32 : 44)
                Text(item.plainText ?? "File")
                    .font(Tokens.bodyMono)
                    .lineLimit(bodyLineLimit(standard: 6, compact: 3))
            }
        case .color:
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Tokens.color(fromHex: item.plainText ?? ""))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(item.plainText ?? "")
                    .font(Tokens.bodyMono)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Image(systemName: footerGlyph)
                .font(.system(size: 9))
            Text(footerText)
                .font(Tokens.caption)
                .lineLimit(1)
        }
        .foregroundStyle(.tertiary)
    }

    private var footerGlyph: String {
        switch item.kind {
        case .text, .richText: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        case .color: return "paintpalette"
        }
    }

    private var footerText: String {
        switch item.kind {
        case .text, .richText:
            if item.sizeBytes > 100_000 {
                return ByteCountFormatter.string(fromByteCount: Int64(item.sizeBytes), countStyle: .file)
            }
            return "\(item.plainText?.count ?? 0) characters"
        case .link:
            return URL(string: item.plainText ?? "")?.host ?? "Link"
        case .image:
            return "Image"
        case .file:
            let count = item.plainText?.components(separatedBy: "\n").count ?? 1
            return count == 1 ? "1 file" : "\(count) files"
        case .color:
            return "Color"
        }
    }
}

struct LinkFaviconView: View {
    let item: ClipItem
    let store: ItemStore
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "link")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 16, height: 16)
        .onAppear {
            if image == nil {
                image = FaviconCache.shared.cached(for: item)
                if image == nil {
                    FaviconCache.shared.favicon(for: item, store: store) { image = $0 }
                }
            }
        }
    }
}

/// Card click handling. The double-tap recognizer must be registered before the
/// single-tap one, or SwiftUI never resolves the double-click. We attach it ONLY in
/// double-click-to-paste mode: in single-click-paste mode a lone single-tap recognizer
/// pastes immediately, with none of the double-click-interval latency an always-present
/// count:2 recognizer would impose on every click. The count:2 gesture carries no
/// modifier flags, which is fine: pasting on double-click is a no-modifier gesture, and
/// modifier multi-select stays a single-click action (see ShelfViewModel.handleCardClick).
private struct CardClickGesture: ViewModifier {
    let doubleClickToPaste: Bool
    let onClick: (NSEvent.ModifierFlags) -> Void
    let onDoubleClick: () -> Void

    func body(content: Content) -> some View {
        if doubleClickToPaste {
            content
                .onTapGesture(count: 2) { onDoubleClick() }
                .onTapGesture(count: 1) { onClick(NSEvent.modifierFlags) }
        } else {
            content
                .onTapGesture(count: 1) { onClick(NSEvent.modifierFlags) }
        }
    }
}

struct CardThumbnail: View {
    let item: ClipItem
    let store: ItemStore
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear {
            if image == nil {
                image = ThumbnailCache.shared.cached(for: item)
                if image == nil {
                    ThumbnailCache.shared.thumbnail(for: item, store: store) { image = $0 }
                }
            }
        }
    }
}
