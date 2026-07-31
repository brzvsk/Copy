import Foundation

/// A faceted shelf-search query: optional free text (FTS over plainText/title/OCR) plus
/// zero or more facets, combined with AND. Built by the app's token field and consumed by
/// `ItemStore.search(filter:)` (text present) or `ItemStore.observeRecent(filter:)` (text
/// empty, so results stay live). Within a facet the sets are OR (kind IN …, pinboardId IN …);
/// across facets it's AND.
public struct SearchFilter: Equatable, Sendable {
    public var text: String
    public var appBundleID: String?
    public var kinds: Set<ItemKind>
    /// Matched against `lastUsedAt` — consistent with ordering, retention, and the relative
    /// timestamps shown on cards. Half-open `[start, end)`.
    public var dateRange: DateInterval?
    public var favoritesOnly: Bool
    public var pinboardIDs: Set<Int64>

    public init(text: String = "",
                appBundleID: String? = nil,
                kinds: Set<ItemKind> = [],
                dateRange: DateInterval? = nil,
                favoritesOnly: Bool = false,
                pinboardIDs: Set<Int64> = []) {
        self.text = text
        self.appBundleID = appBundleID
        self.kinds = kinds
        self.dateRange = dateRange
        self.favoritesOnly = favoritesOnly
        self.pinboardIDs = pinboardIDs
    }

    /// No text and no facets — the plain browse case.
    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && appBundleID == nil
            && kinds.isEmpty
            && dateRange == nil
            && !favoritesOnly
            && pinboardIDs.isEmpty
    }

    /// Whether there is any free text to FTS-match (facets alone don't need FTS).
    public var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// One app that appears in the clipboard history, with how many items it produced. Powers
/// the search field's app suggestions (`ItemStore.distinctApps()`).
public struct AppUsage: Equatable, Sendable {
    public let bundleID: String
    public let name: String
    public let count: Int

    public init(bundleID: String, name: String, count: Int) {
        self.bundleID = bundleID
        self.name = name
        self.count = count
    }
}
