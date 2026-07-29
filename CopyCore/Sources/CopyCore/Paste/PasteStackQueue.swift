public struct PasteStackQueue: Equatable, Sendable {
    public private(set) var itemUUIDs: [String] = []
    public var isLIFO = false

    public init() {}

    public mutating func enqueue(_ uuid: String) {
        if let index = itemUUIDs.firstIndex(of: uuid) {
            itemUUIDs.remove(at: index)
        }
        itemUUIDs.append(uuid)
    }

    public mutating func remove(_ uuid: String) {
        itemUUIDs.removeAll { $0 == uuid }
    }

    public mutating func move(from: Int, to: Int) {
        guard from >= 0, from < itemUUIDs.count,
              to >= 0, to < itemUUIDs.count else {
            return
        }
        let item = itemUUIDs.remove(at: from)
        itemUUIDs.insert(item, at: to)
    }

    public mutating func clear() {
        itemUUIDs.removeAll()
    }

    public var next: String? {
        isLIFO ? itemUUIDs.last : itemUUIDs.first
    }

    @discardableResult
    public mutating func advance() -> String? {
        guard !itemUUIDs.isEmpty else { return nil }
        let index = isLIFO ? itemUUIDs.count - 1 : 0
        return itemUUIDs.remove(at: index)
    }

    public var isEmpty: Bool {
        itemUUIDs.isEmpty
    }

    public var count: Int {
        itemUUIDs.count
    }
}
