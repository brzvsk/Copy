import AppKit
import CopyCore
import SwiftUI

/// Content of the floating Paste Stack palette (`PasteStackController` hosts this). The
/// queue is shown in paste order: each row is numbered by when it will be pasted, and
/// the one that Command V will paste next is marked. Reorders via drag (`.onMove`),
/// removes rows via swipe or context menu, flips which end pastes first, and clears the
/// queue. `onContentChange` fires whenever the queue's uuids change so the controller can
/// re-fit the panel's height to the new row count (see `PasteStackController.resizeToFit()`).
struct PasteStackView: View {
    @Bindable var model: PasteStackModel
    var onClose: () -> Void = {}
    var onContentChange: () -> Void = {}

    var body: some View {
        // Resolved once per body evaluation and threaded through to `header(count:)`
        // and `list(items:)` below — `model.items()` is a pure read (see its doc
        // comment), but calling it multiple times per render would still mean
        // resolving the same uuids against the store redundantly.
        let items = model.items()
        VStack(spacing: 0) {
            header(count: items.count)
            Divider()
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    list(items: items)
                }
            }
            .frame(maxHeight: .infinity)
            Divider()
            footer(hasItems: !items.isEmpty)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(cornerRadius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onChange(of: model.queue.itemUUIDs) { _, _ in onContentChange() }
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Paste Stack")
                .font(.system(size: 13, weight: .semibold))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5)))
            }
            Spacer()
            closeButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Branched rather than chained (`.buttonStyle(.plain).buttonStyle(.glass)`) to
    /// avoid relying on SwiftUI's `buttonStyle` override-ordering for two different
    /// styles on one button. `.glass` gives this dismiss control the small circular
    /// glass-pill treatment Apple's own floating glass panels use for icon-only close
    /// buttons on macOS 26; pre-26 it's the original quiet `.plain` icon, unchanged.
    @ViewBuilder
    private var closeButton: some View {
        let button = Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Close Paste Stack")

        if #available(macOS 26, *) {
            button.buttonStyle(.glass)
        } else {
            button.buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.stack")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Your paste stack is empty")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Copy items or add cards from the shelf, then press Command V to paste through them.")
                .font(Tokens.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 16)
    }

    private func list(items: [ClipItem]) -> some View {
        let order = pasteNumbers(for: items)
        return List {
            ForEach(items, id: \.uuid) { item in
                PasteStackRow(item: item,
                              number: order[item.uuid] ?? 0,
                              isNext: order[item.uuid] == 1)
                    .swipeActions {
                        Button("Remove", role: .destructive) {
                            model.queue.remove(item.uuid)
                        }
                    }
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            model.queue.remove(item.uuid)
                        }
                    }
            }
            .onMove(perform: move)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    /// Maps each item's uuid to its 1-based paste position. Row 1 is whatever Command V
    /// pastes next: the first-added item under "Oldest first" (FIFO), or the last-added
    /// under "Newest first" (LIFO). `model.items()` is in insertion order, so LIFO
    /// numbers from the bottom up. Mirrors `PasteStackQueue.peek`/`dequeue`.
    private func pasteNumbers(for items: [ClipItem]) -> [String: Int] {
        let isLIFO = model.queue.isLIFO
        var map: [String: Int] = [:]
        for (index, item) in items.enumerated() {
            map[item.uuid] = isLIFO ? (items.count - index) : (index + 1)
        }
        return map
    }

    /// `List.onMove` hands a `destination` that can equal the row count (drop past the
    /// last row); `PasteStackQueue.move(from:to:)` requires `to < count`, so translate
    /// down by one whenever the drop lands after the source's original position.
    private func move(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first else { return }
        let target = destination > sourceIndex ? destination - 1 : destination
        model.queue.move(from: sourceIndex, to: target)
    }

    private func footer(hasItems: Bool) -> some View {
        VStack(spacing: 8) {
            Picker("Paste order", selection: $model.queue.isLIFO) {
                Text("Oldest first").tag(false)
                Text("Newest first").tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Paste order")

            if hasItems {
                Text("Press Command V to paste the next item.")
                    .font(Tokens.caption)
                    .foregroundStyle(.tertiary)
            }

            clearButton
                .disabled(!hasItems)
        }
        .padding(12)
    }

    /// Same branch-not-chain reasoning as `closeButton` above.
    @ViewBuilder
    private var clearButton: some View {
        let button = Button("Clear") {
            model.queue.clear()
        }
        .frame(maxWidth: .infinity)

        if #available(macOS 26, *) {
            button.buttonStyle(.glass)
        } else {
            button
        }
    }
}

private struct PasteStackRow: View {
    let item: ClipItem
    let number: Int
    let isNext: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isNext ? Color.white : Color.secondary)
                .frame(width: 20, height: 20)
                .background(
                    Circle().fill(isNext
                                  ? Color.accentColor
                                  : Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                )
                .accessibilityLabel(isNext ? "Next, position \(number)" : "Position \(number)")
            Image(systemName: glyph)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(item.displayTitle)
                .font(Tokens.bodyMono)
                .lineLimit(1)
            Spacer(minLength: 0)
            if isNext {
                Text("Next")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
            }
        }
        .padding(.vertical, 3)
    }

    private var glyph: String {
        switch item.kind {
        case .text, .richText: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        case .color: return "paintpalette"
        }
    }
}
