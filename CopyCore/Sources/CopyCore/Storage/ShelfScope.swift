public enum ShelfScope: String, CaseIterable, Sendable {
    case all, text, images, links, files

    /// nil means no kind filter.
    public var kinds: Set<ItemKind>? {
        switch self {
        case .all: return nil
        case .text: return [.text, .richText]
        case .images: return [.image]
        case .links: return [.link]
        case .files: return [.file]
        }
    }

    public var title: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .images: return "Images"
        case .links: return "Links"
        case .files: return "Files"
        }
    }
}
