public enum CopyPasteboard {
    /// Pasteboard type Copy attaches to its own writes so the monitor skips them.
    public static let selfMarkerType = "sk.brzv.copy.self"

    /// NSPasteboard.PasteboardType.color's raw value.
    public static let colorType = "com.apple.cocoa.pasteboard.color"

    /// Favicon representation UTI for link metadata.
    public static let faviconUTI = "sk.brzv.copy.favicon"

}
