import AppKit

public protocol PasteboardReading {
    var changeCount: Int { get }
    func typeIdentifiers() -> [String]
    func data(forUTI uti: String) -> Data?
    func string() -> String?
    func fileURLs() -> [URL]
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
}
