import AppKit
import CopyCore
import SwiftUI

/// Content of the floating Paste Stack palette (`PasteStackController` hosts this). The
/// queue is shown in paste order: each row is numbered by when it will be pasted, and the
/// one that Command V pastes next is marked. Entries can be added (the header +, which
/// queues the latest copy), edited in place (double-click or the pencil), removed (the
/// trash, swipe, or context menu), and reordered by drag. `onContentChange` fires whenever
/// the queue's uuids change so the controller can re-fit the panel's height.
struct PasteStackView: View {
    @Bindable var model: PasteStackModel
    var onClose: () -> Void = {}
    var onContentChange: () -> Void = {}

    @State private var editingUUID: String?
    @State private var editText: String = ""

    /// Reads `model.revision` (so an in-place edit re-renders) and resolves the queue's
    /// uuids to items once per body evaluation.
    private var resolvedItems: [ClipItem] {
        _ = model.revision
        return model.items()
    }

    var body: some View {
        let items = resolvedItems
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
            // The order picker and Clear only make sense with items in the queue; hiding
            // them when empty keeps the empty palette clean.
            if !items.isEmpty {
                Divider()
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(cornerRadius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onChange(of: model.queue.itemUUIDs) { _, _ in onContentChange() }
    }

    // MARK: Header

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
            if count > 0 {
                IconButton(systemName: "trash", help: "Clear the stack") { model.queue.clear() }
            }
            IconButton(systemName: "plus", help: "Add the latest copy") { model.addMostRecent() }
            IconButton(systemName: "xmark", help: "Close") { onClose() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.stack")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Nothing queued")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Add a copy with +, then ⌘V walks the stack.")
                .font(Tokens.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 16)
    }

    // MARK: List

    private func list(items: [ClipItem]) -> some View {
        let order = pasteNumbers(for: items)
        return List {
            ForEach(items, id: \.uuid) { item in
                PasteStackRow(
                    item: item,
                    number: order[item.uuid] ?? 0,
                    isNext: order[item.uuid] == 1,
                    isEditing: editingUUID == item.uuid,
                    editText: $editText,
                    onBeginEdit: { beginEdit(item) },
                    onCommitEdit: { commitEdit(item) },
                    onCancelEdit: { editingUUID = nil },
                    onRemove: { model.queue.remove(item.uuid) }
                )
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                .listRowSeparator(.hidden)
                .swipeActions {
                    Button("Remove", role: .destructive) { model.queue.remove(item.uuid) }
                }
                .contextMenu {
                    Button("Edit…") { beginEdit(item) }
                        .disabled(!isEditable(item))
                    Button("Remove", role: .destructive) { model.queue.remove(item.uuid) }
                }
            }
            .onMove(perform: move)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func isEditable(_ item: ClipItem) -> Bool {
        switch item.kind {
        case .text, .richText, .link: return true
        case .image, .file, .color: return false
        }
    }

    private func beginEdit(_ item: ClipItem) {
        guard isEditable(item) else { return }
        editText = item.plainText ?? ""
        editingUUID = item.uuid
    }

    private func commitEdit(_ item: ClipItem) {
        let trimmed = editText
        editingUUID = nil
        guard !trimmed.isEmpty, trimmed != item.plainText else { return }
        model.updateText(item, to: trimmed)
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

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 8) {
            Picker("Paste order", selection: $model.queue.isLIFO) {
                Text("Oldest first").tag(false)
                Text("Newest first").tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Paste order")

            Text("⌘V pastes the next item.")
                .font(Tokens.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct PasteStackRow: View {
    let item: ClipItem
    let number: Int
    let isNext: Bool
    let isEditing: Bool
    @Binding var editText: String
    let onBeginEdit: () -> Void
    let onCommitEdit: () -> Void
    let onCancelEdit: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false
    @FocusState private var fieldFocused: Bool

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

            if isEditing {
                TextField("Edit", text: $editText)
                    .textFieldStyle(.plain)
                    .font(Tokens.bodyMono)
                    .focused($fieldFocused)
                    .onAppear { DispatchQueue.main.async { fieldFocused = true } }
                    .onSubmit(onCommitEdit)
                    .onExitCommand(perform: onCancelEdit)
                    .onChange(of: fieldFocused) { _, focused in if !focused { onCommitEdit() } }
            } else {
                Text(item.displayTitle)
                    .font(Tokens.bodyMono)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isEditing {
                EmptyView()
            } else if isHovering {
                rowActions
            } else if isNext {
                Text("Next")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { onBeginEdit() }
    }

    private var rowActions: some View {
        HStack(spacing: 1) {
            IconButton(systemName: "pencil", fontSize: 10,
                       size: CGSize(width: 22, height: 22), help: "Edit", action: onBeginEdit)
            IconButton(systemName: "trash", fontSize: 10,
                       size: CGSize(width: 22, height: 22), help: "Remove", action: onRemove)
        }
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
