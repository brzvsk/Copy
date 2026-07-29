public struct ShelfSelection: Equatable, Sendable {
    public private(set) var primary: String?
    public private(set) var selected: Set<String> = []

    public init() {}

    public mutating func reset() {
        primary = nil
        selected = []
    }

    public mutating func click(_ uuid: String) {
        primary = uuid
        selected = [uuid]
    }

    public mutating func commandClick(_ uuid: String) {
        if selected.contains(uuid) {
            selected.remove(uuid)
            if primary == uuid { primary = selected.first }
        } else {
            selected.insert(uuid)
            primary = uuid
        }
    }

    public mutating func shiftClick(_ uuid: String, in order: [String]) {
        guard let anchor = primary,
              let anchorIndex = order.firstIndex(of: anchor),
              let targetIndex = order.firstIndex(of: uuid) else {
            click(uuid)
            return
        }
        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selected = Set(order[range])
    }

    public mutating func move(_ delta: Int, in order: [String]) {
        guard !order.isEmpty else { return }
        guard let current = primary, let index = order.firstIndex(of: current) else {
            let target = delta >= 0 ? order.first! : order.last!
            click(target)
            return
        }
        let next = max(0, min(order.count - 1, index + delta))
        click(order[next])
    }

    public func orderedSelection(in order: [String]) -> [String] {
        order.filter(selected.contains)
    }

    public mutating func prune(existing: Set<String>, order: [String]) {
        selected = selected.intersection(existing)
        if let primary, !existing.contains(primary) {
            self.primary = order.first(where: selected.contains) ?? order.first
            if let newPrimary = self.primary, selected.isEmpty {
                selected = [newPrimary]
            }
        }
        if existing.isEmpty {
            reset()
        }
    }
}
