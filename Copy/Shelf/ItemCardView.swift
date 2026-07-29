import SwiftUI
import CopyCore
import UniformTypeIdentifiers

struct ItemCardView: View {
    let item: ClipItem
    let isSelected: Bool
    let store: ItemStore
    let onPaste: () -> Void
    let onPastePlain: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    let dragProvider: () -> NSItemProvider

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Tokens.spineColor(forBundleID: item.appBundleID))
                .frame(width: Tokens.spineWidth)
            VStack(alignment: .leading, spacing: 6) {
                header
                body(for: item.kind)
                Spacer(minLength: 0)
                footer
            }
            .padding(10)
        }
        .frame(width: Tokens.cardWidth, height: Tokens.cardHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
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
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        .contextMenu {
            Button("Paste", action: onPaste)
            Button("Paste as plain text", action: onPastePlain)
            Divider()
            Button(item.isFavorite ? "Remove favorite" : "Favorite", action: onToggleFavorite)
            Button("Delete", role: .destructive, action: onDelete)
        }
        .onDrag(dragProvider)
    }

    private var header: some View {
        HStack(spacing: 5) {
            if let icon = AppIconCache.icon(forBundleID: item.appBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
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

    @ViewBuilder
    private func body(for kind: ItemKind) -> some View {
        switch kind {
        case .text, .richText:
            Text(item.plainText ?? "")
                .font(Tokens.bodyMono)
                .lineLimit(11)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        case .link:
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text(URL(string: item.plainText ?? "")?.host ?? "Link")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(item.plainText ?? "")
                    .font(Tokens.bodyMono)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }
        case .image:
            CardThumbnail(item: item, store: store)
        case .file:
            VStack(alignment: .leading, spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(for: fileType))
                    .resizable()
                    .frame(width: 44, height: 44)
                Text(item.plainText ?? "File")
                    .font(Tokens.bodyMono)
                    .lineLimit(6)
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

    private var fileType: UTType {
        let ext = (item.plainText?.components(separatedBy: "\n").first as NSString?)?.pathExtension ?? ""
        return UTType(filenameExtension: ext) ?? .data
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

struct CardThumbnail: View {
    let item: ClipItem
    let store: ItemStore
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color(nsColor: .quaternaryLabelColor))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
