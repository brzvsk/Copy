import Foundation

public struct CapturedRepresentation: Equatable, Sendable {
    public let uti: String
    public let data: Data

    public init(uti: String, data: Data) {
        self.uti = uti
        self.data = data
    }
}

public struct CapturedItem: Equatable, Sendable {
    public let kind: ItemKind
    public let plainText: String
    /// The bytes that identity-hash this item (dedup key input).
    public let hashData: Data
    public let representations: [CapturedRepresentation]
    public let sourceBundleID: String?
    public let sourceAppName: String?

    public init(kind: ItemKind, plainText: String, hashData: Data,
                representations: [CapturedRepresentation],
                sourceBundleID: String?, sourceAppName: String?) {
        self.kind = kind
        self.plainText = plainText
        self.hashData = hashData
        self.representations = representations
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
    }
}
