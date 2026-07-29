import CryptoKit
import Foundation

public struct BlobStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    @discardableResult
    public func store(_ data: Data) throws -> String {
        let key = Self.key(for: data)
        let url = directory.appendingPathComponent(key)
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        return key
    }

    public func data(forKey key: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(key))
    }

    public func delete(key: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(key))
    }

    public static func key(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
