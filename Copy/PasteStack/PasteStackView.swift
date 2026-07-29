import AppKit
import CopyCore
import SwiftUI

/// Content of the floating Paste Stack palette (`PasteStackController` hosts this).
/// Reorders via drag (`.onMove`), removes rows via swipe or context menu, flips
/// FIFO/LIFO, and clears the queue. `onContentChange` fires whenever the queue's
/// uuids change (enqueue, remove, clear, reorder) so the controller can re-fit the
/// panel's height to the new row count — see `PasteStackController.show()`.
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
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PasteStackBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onChange(of: model.queue.itemUUIDs) { _, _ in onContentChange() }
    }

    private func header(count: Int) -> some View {
        HStack {
            Text("Paste Stack · \(count)")
                .font(Tokens.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Paste Stack")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // Mirrors ShelfRootView's empty state exactly (spacing, icon size/weight, text
    // size/weight) so the two surfaces read as the same design language.
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.stack")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Copy items or add them from the shelf")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 16)
    }

    private func list(items: [ClipItem]) -> some View {
        List {
            ForEach(items, id: \.uuid) { item in
                PasteStackRow(item: item)
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            model.queue.remove(item.uuid)
                        }
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            model.queue.remove(item.uuid)
                        }
                    }
            }
            .onMove(perform: move)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    /// `List.onMove` hands a `destination` that can equal the row count (drop past the
    /// last row); `PasteStackQueue.move(from:to:)` requires `to < count`, so translate
    /// down by one whenever the drop lands after the source's original position.
    private func move(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first else { return }
        let target = destination > sourceIndex ? destination - 1 : destination
        model.queue.move(from: sourceIndex, to: target)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Picker("Order", selection: $model.queue.isLIFO) {
                Text("FIFO").tag(false).help("First in, first out")
                Text("LIFO").tag(true).help("Last in, first out")
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)

            Button("Clear") {
                model.queue.clear()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
    }
}

private struct PasteStackRow: View {
    let item: ClipItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: glyph)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(item.menuTitle)
                .font(Tokens.bodyMono)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
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

private struct PasteStackBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
