import AppKit
import CopyCore
import SwiftUI

/// Content of the floating Paste Stack palette (`PasteStackController` hosts this).
///
/// The palette is a non-activating, never-key panel (so plain ⌘V keeps going to the app
/// underneath). SwiftUI's `List` and the drag-and-drop system are unreliable in that
/// context, so this is a plain `ScrollView` of fixed-height rows, and reordering is done
/// with a direct drag gesture that offsets rows live and commits the move on release — no
/// dependence on window focus. Entries can be added (header +, queues the latest copy),
/// edited in place (double-click or the pencil), removed (trash on hover or the context
/// menu), reordered by dragging, and cleared (header trash).
struct PasteStackView: View {
    @Bindable var model: PasteStackModel
    var onClose: () -> Void = {}
    var onContentChange: () -> Void = {}

    @State private var editingUUID: String?
    @State private var editText = ""
    @State private var draggingUUID: String?
    @State private var dragTranslation: CGFloat = 0

    static let rowHeight: CGFloat = 36

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
            Spacer(minLength: 8)
            if count > 0 {
                IconButton(systemName: "trash", help: "Clear the stack") { model.queue.clear() }
            }
            IconButton(systemName: "plus", help: "Add the latest copy") { model.addMostRecent() }
            IconButton(systemName: "xmark", help: "Close") { onClose() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        // The header is the window's drag handle (the buttons are controls, so they click
        // rather than drag). `.background` sizes to the header, so it never grows the row.
        .background(WindowMoveArea())
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
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.uuid) { index, item in
                    PasteStackRow(
                        item: item,
                        number: order[item.uuid] ?? 0,
                        isNext: order[item.uuid] == 1,
                        isEditing: editingUUID == item.uuid,
                        isDragging: draggingUUID == item.uuid,
                        editText: $editText,
                        onBeginEdit: { beginEdit(item) },
                        onCommitEdit: { commitEdit(item) },
                        onCancelEdit: { editingUUID = nil },
                        onRemove: { model.queue.remove(item.uuid) }
                    )
                    .frame(height: Self.rowHeight)
                    // Rows aren't window-draggable, so a drag here reorders (below) instead
                    // of moving the window.
                    .background(WindowFixedArea())
                    .offset(y: dragYOffset(uuid: item.uuid, index: index, items: items))
                    .zIndex(draggingUUID == item.uuid ? 1 : 0)
                    .gesture(reorderGesture(item: item, items: items))
                    .contextMenu {
                        Button("Edit…") { beginEdit(item) }.disabled(!isEditable(item))
                        Button("Remove", role: .destructive) { model.queue.remove(item.uuid) }
                    }
                }
            }
            // A real backing view so the wheel scrolls even over the gaps between rows.
            .background(Color.black.opacity(0.001))
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: Reorder (direct drag, no drag-and-drop system)

    private func reorderGesture(item: ClipItem, items: [ClipItem]) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                if draggingUUID == nil { draggingUUID = item.uuid }
                dragTranslation = value.translation.height
            }
            .onEnded { _ in
                defer { draggingUUID = nil; dragTranslation = 0 }
                guard let dragging = draggingUUID,
                      let source = items.firstIndex(where: { $0.uuid == dragging }) else { return }
                let target = clampedTarget(source: source, count: items.count)
                if target != source {
                    withAnimation(.easeInOut(duration: 0.16)) { model.queue.move(from: source, to: target) }
                }
            }
    }

    /// Where the dragged row would land, from how many row-heights it's been dragged.
    private func clampedTarget(source: Int, count: Int) -> Int {
        let delta = Int((dragTranslation / Self.rowHeight).rounded())
        return min(max(source + delta, 0), count - 1)
    }

    /// The dragged row follows the cursor; the rows it's passing over slide aside to open
    /// a gap at the drop target.
    private func dragYOffset(uuid: String, index: Int, items: [ClipItem]) -> CGFloat {
        guard let dragging = draggingUUID,
              let source = items.firstIndex(where: { $0.uuid == dragging }) else { return 0 }
        if uuid == dragging { return dragTranslation }
        let target = clampedTarget(source: source, count: items.count)
        if source < target, index > source, index <= target { return -Self.rowHeight }
        if source > target, index < source, index >= target { return Self.rowHeight }
        return 0
    }

    // MARK: Edit

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
        let text = editText
        editingUUID = nil
        guard !text.isEmpty, text != item.plainText else { return }
        model.updateText(item, to: text)
    }

    /// Maps each item's uuid to its 1-based paste position. Row 1 is whatever Command V
    /// pastes next: the first-added under "Oldest first" (FIFO) or the last-added under
    /// "Newest first" (LIFO). `model.items()` is in insertion order, so LIFO numbers from
    /// the bottom up.
    private func pasteNumbers(for items: [ClipItem]) -> [String: Int] {
        let isLIFO = model.queue.isLIFO
        var map: [String: Int] = [:]
        for (index, item) in items.enumerated() {
            map[item.uuid] = isLIFO ? (items.count - index) : (index + 1)
        }
        return map
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

            Text("⌘V pastes the next item · drag to reorder")
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
    var isDragging: Bool = false
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
                    Circle().fill(isNext ? Color.accentColor : Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                )

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

            if !isEditing {
                if isHovering {
                    HStack(spacing: 1) {
                        IconButton(systemName: "pencil", fontSize: 10,
                                   size: CGSize(width: 22, height: 22), help: "Edit", action: onBeginEdit)
                        IconButton(systemName: "trash", fontSize: 10,
                                   size: CGSize(width: 22, height: 22), help: "Remove", action: onRemove)
                    }
                } else if isNext {
                    Text("Next")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isDragging ? Color.primary.opacity(0.08) : (isHovering ? Color.primary.opacity(0.04) : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isDragging ? Color(nsColor: .separatorColor) : .clear, lineWidth: 1)
        )
        .shadow(color: isDragging ? .black.opacity(0.2) : .clear, radius: isDragging ? 6 : 0, y: 2)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { onBeginEdit() }
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
