import AppKit

public protocol PasteboardReading {
    var changeCount: Int { get }
    func typeIdentifiers() -> [String]
    func data(forUTI uti: String) -> Data?
    func string() -> String?
    func fileURLs() -> [URL]
    func colorHex() -> String?
}

extension NSPasteboard: PasteboardReading {
    public func typeIdentifiers() -> [String] {
        (types ?? []).map(\.rawValue)
    }

    public func data(forUTI uti: String) -> Data? {
        data(forType: NSPasteboard.PasteboardType(uti))
    }

    public func string() -> String? {
        string(forType: .string)
    }

    public func fileURLs() -> [URL] {
        (readObjects(forClasses: [NSURL.self],
                     options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    public func colorHex() -> String? {
        guard let color = (readObjects(forClasses: [NSColor.self]) as? [NSColor])?.first,
              let srgb = color.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int(round(srgb.redComponent * 255)),
                      Int(round(srgb.greenComponent * 255)),
                      Int(round(srgb.blueComponent * 255)))
    }
}
