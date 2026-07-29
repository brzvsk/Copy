public enum CopyPasteboard {
    /// Pasteboard type Copy attaches to its own writes so the monitor skips them.
    public static let selfMarkerType = "com.tarikbc.copy.self"

    /// NSPasteboard.PasteboardType.color's raw value.
    public static let colorType = "com.apple.cocoa.pasteboard.color"

    /// Favicon representation UTI for link metadata.
    public static let faviconUTI = "com.tarikbc.copy.favicon"

    /// Marks a synthesized ⌘V's CGEvent (`eventSourceUserData`) as Copy's own, so any
    /// tap watching for a *user-initiated* ⌘V — e.g. `PasteStackEngine`'s CGEvent tap —
    /// lets it straight through instead of intercepting it. Every place Copy posts its
    /// own ⌘V (`CGKeyEventPoster.postCommandV()`, `PasteStackEngine.postMarkedPasteKeystroke()`)
    /// must set this field so there is exactly one definition of "this is our keystroke."
    public static let selfEventUserData: Int64 = 0xC0_50_11
}
