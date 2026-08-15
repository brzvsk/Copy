import Foundation

/// The growing fetch window behind shelf scrolling. The shelf's history query is bounded by
/// a `LIMIT`, so a fixed bound is a hard floor on how far back the user can scroll no matter
/// what the retention setting keeps. This widens that bound as scrolling nears the oldest
/// loaded row, letting the shelf walk the whole history a page at a time instead of fetching
/// everything up front on every capture.
///
/// Owned by the app's shelf view model: it calls `growIfNeeded` from each card as the card
/// scrolls into view, re-runs its query with the new `limit` when that returns `true`, and
/// calls `reset()` whenever the query itself changes.
public struct PageWindow: Equatable, Sendable {
    /// Rows in the first page, and the value `reset()` returns to.
    public let pageSize: Int
    /// Rows added to `limit` each time the window grows.
    public let growth: Int
    /// How many rows from the end of the loaded rows trigger the next growth, so the window
    /// widens before the user actually reaches the last one.
    public let lookahead: Int

    /// The row count the caller's query should currently fetch.
    public private(set) var limit: Int

    public init(pageSize: Int = 100, growth: Int = 200, lookahead: Int = 20) {
        self.pageSize = pageSize
        self.growth = growth
        self.lookahead = lookahead
        self.limit = pageSize
    }

    /// Narrows back to the first page. The caller uses this when the query changes, so a new
    /// query never inherits the previous one's window.
    public mutating func reset() {
        limit = pageSize
    }

    /// Widens the window when `visibleIndex` is within `lookahead` rows of the end of the
    /// `loadedCount` rows already delivered. Returns whether the caller should re-run its
    /// query against the new `limit`.
    ///
    /// `loadedCount >= limit` does double duty. It's the "there may be more rows" test — a
    /// short page means the query is exhausted, so the window stops growing and the caller
    /// stops re-querying. It's also the re-entrancy guard: immediately after a growth the
    /// delivered rows are still the narrower page, so the further calls that arrive while
    /// the wider fetch is in flight are ignored rather than compounding the growth.
    public mutating func growIfNeeded(visibleIndex: Int, loadedCount: Int) -> Bool {
        guard visibleIndex >= loadedCount - lookahead, loadedCount >= limit else { return false }
        limit += growth
        return true
    }
}
