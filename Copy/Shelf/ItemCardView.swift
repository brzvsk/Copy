import SwiftUI
import CopyCore

struct ItemCardView: View {
    let item: ClipItem
    let isSelected: Bool
    /// Whether this card's title is currently the inline click-to-edit field rather
    /// than static `Text` — mirrors `ShelfViewModel.inlineRenamingItemID == item.id`,
    /// computed by the caller since this view has no view-model access of its own.
    let isInlineRenaming: Bool
    let store: ItemStore
    let pinboards: [Pinboard]
    let currentPinboardID: Int64?
    /// Compact shelf mode (`SettingsStore.compactShelf`, threaded from `ShelfRootView`):
    /// smaller card frame + tighter line limits so more cards fit on screen at once.
    var compact: Bool = false
    let doubleClickToPaste: Bool
    /// The active search text, used to show and highlight the matched OCR snippet under
    /// an image result. Empty when not searching.
    var searchQuery: String = ""
    let onClick: (NSEvent.ModifierFlags) -> Void
    let onDoubleClick: () -> Void
    let onPaste: () -> Void
    let onPastePlain: () -> Void
    let onEdit: () -> Void
    let onAdjustColor: () -> Void
    /// Enters inline title-editing (see `isInlineRenaming`) — wired from both the
    /// title text's tap gesture and the context menu's "Rename…" item.
    let onBeginInlineRename: () -> Void
    let onCommitInlineRename: (String) -> Void
    let onCancelInlineRename: () -> Void
    let onToggleFavorite: () -> Void
    let onAddToPinboard: (Int64) -> Void
    let onRemoveFromPinboard: () -> Void
    let onAddToPasteStack: () -> Void
    let onCopyText: () -> Void
    let onQuickLook: () -> Void
    let onOpen: () -> Void
    let onRotate: (Bool) -> Void
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

    /// Whether the card shows the title row above the body — either the user-assigned
    /// `item.title` as static text, or the inline edit field while renaming (which
    /// also shows for a titleless item mid-rename, so it has somewhere to type). When
    /// true, `bodyLineLimit(standard:compact:)` trims one line off the body's limit in
    /// both layout modes, since that row eats into the same fixed-height card without
    /// shrinking anything else.
    private var hasCustomTitle: Bool {
        if isInlineRenaming { return true }
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
            if isInlineRenaming {
                InlineTitleField(
                    initialText: item.title ?? "",
                    onCommit: onCommitInlineRename,
                    onCancel: onCancelInlineRename
                )
            } else if let title = item.title, !title.isEmpty {
                Text(title)
                    .font(Tokens.cardSubtitle)
                    .lineLimit(1)
                    // Scoped to the title text only, so it wins over `CardClickGesture`
                    // on the card body below (SwiftUI resolves a tap to the deepest
                    // view carrying a gesture) — clicking the title never also
                    // selects/pastes the card.
                    .onTapGesture { onBeginInlineRename() }
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
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.03)],
                                startPoint: .top, endPoint: .bottom)
                        )
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
        // A soft accent glow lifts the selected card off the row, matching the shelf's
        // Liquid Glass depth. Clear (no glow) when unselected.
        .shadow(color: isSelected ? Color.accentColor.opacity(0.35) : .clear,
                radius: isSelected ? 9 : 0, y: 1)
        .contextMenu {
            Button("Paste", action: onPaste)
            Button("Paste as Plain Text", action: onPastePlain)
            if item.kind == .link || item.kind == .file {
                Button("Open", action: onOpen)
                    .keyboardShortcut("o", modifiers: .command)
            }
            if item.recognizedText?.isEmpty == false {
                Button("Copy Text", action: onCopyText)
            }
            if item.kind == .file, !quickLookURLs.isEmpty {
                Button("Quick Look", action: onQuickLook)
            }
            if item.kind == .image {
                Button("Rotate Left") { onRotate(false) }
                Button("Rotate Right") { onRotate(true) }
            }
            Divider()
            if isEditable {
                Button("Edit…", action: onEdit)
                    .keyboardShortcut("e", modifiers: .command)
            } else if item.kind == .color {
                Button("Adjust Color…", action: onAdjustColor)
            }
            Button("Rename…", action: onBeginInlineRename)
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

    /// Text/rich-text card body. When the whole item is a hex color (e.g. someone
    /// copied "#4C9DFF"), show the actual color as a swatch instead of the raw string;
    /// otherwise render the (optionally code-highlighted) text. Extracted from
    /// `body(for:)` to keep that switch simple enough for the Swift type checker.
    @ViewBuilder
    private var textBody: some View {
        if let hex = HexColor.normalized(item.plainText ?? "") {
            colorSwatchBody(hex)
        } else {
            codeAwareBody(text: item.plainText ?? "", cap: 1_500)
                .font(Tokens.bodyMono)
                .lineLimit(bodyLineLimit(standard: 11, compact: 6))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// A color swatch plus its hex, matching the `.color` card, used for both real
    /// color items and text items that are themselves a hex color.
    private func colorSwatchBody(_ hex: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Tokens.color(fromHex: hex))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(hex).font(Tokens.bodyMono)
        }
    }

    /// Image card body: the thumbnail, plus a highlighted OCR snippet when a search
    /// matched the image's recognized text. Extracted from `body(for:)` so the switch
    /// there stays simple enough for the Swift type checker.
    @ViewBuilder
    private var imageBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardThumbnail(item: item, store: store)
            if !searchQuery.isEmpty, let ocr = item.recognizedText,
               let snippet = OCRSnippet.make(recognizedText: ocr, query: searchQuery) {
                highlightedSnippet(snippet, query: searchQuery)
                    .font(Tokens.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Renders an OCR snippet with the matched query span tinted, so an image search
    /// result shows why it matched. Content coloring only (no card stripe).
    private func highlightedSnippet(_ snippet: String, query: String) -> Text {
        guard let range = snippet.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return Text(snippet)
        }
        let before = String(snippet[snippet.startIndex..<range.lowerBound])
        let match = String(snippet[range])
        let after = String(snippet[range.upperBound..<snippet.endIndex])
        return Text(before) + Text(match).foregroundColor(.accentColor).fontWeight(.semibold) + Text(after)
    }

    @ViewBuilder
    private func body(for kind: ItemKind) -> some View {
        switch kind {
        case .text, .richText:
            textBody
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
            imageBody
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

/// Inline, click-to-edit title field shown in place of the title `Text` while a
/// card is being renamed (`ItemCardView.isInlineRenaming`). Enter commits, Escape
/// reverts without saving, and losing focus (clicking away) commits — the field
/// is auto-focused on appear so typing can start immediately.
private struct InlineTitleField: View {
    let initialText: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool
    /// Guards `commit()`/`cancel()` against running twice for the same edit: Return
    /// fires `.onSubmit` (commit), Escape fires `.onExitCommand` (cancel), and
    /// `.onDisappear` (below) commits as a catch-all when the field leaves the tree
    /// for any other reason — each of those also drops focus as a side effect, which
    /// would otherwise re-trigger the `onChange(of: isFocused)` focus-loss commit on
    /// the same resolution.
    @State private var isResolved = false

    init(initialText: String, onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initialText = initialText
        self.onCommit = onCommit
        self.onCancel = onCancel
        _text = State(initialValue: initialText)
    }

    var body: some View {
        TextField("Title", text: $text)
            .textFieldStyle(.plain)
            .font(Tokens.cardSubtitle)
            .lineLimit(1)
            .focused($isFocused)
            .onAppear {
                // Dispatched async: this field lives inside a LazyHStack card row, and
                // focusing synchronously on `.onAppear` can lose the race with SwiftUI
                // still installing the view in the window's responder chain.
                DispatchQueue.main.async { isFocused = true }
            }
            .onSubmit { commit() }
            .onExitCommand { cancel() }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            // Catch-all for teardown paths `onChange(of: isFocused)` doesn't reliably
            // cover — e.g. this card's `isInlineRenaming` flips to false because a
            // DIFFERENT card started renaming (branch-swap back to the title `Text`,
            // not a focus change on this view), or the row disappears from the shelf
            // entirely mid-edit. `.onDisappear` always fires when a view leaves the
            // render tree, so an in-progress edit is saved rather than silently
            // dropped. `isResolved` keeps this a no-op after Enter/Esc already
            // resolved the edit.
            .onDisappear { commit() }
    }

    private func commit() {
        guard !isResolved else { return }
        isResolved = true
        onCommit(text)
    }

    private func cancel() {
        guard !isResolved else { return }
        isResolved = true
        onCancel()
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
