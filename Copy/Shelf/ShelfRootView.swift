import SwiftUI
import CopyCore
import AppKit
import UniformTypeIdentifiers

struct ShelfRootView: View {
    @Bindable var viewModel: ShelfViewModel

    var body: some View {
        VStack(spacing: 0) {
            ShelfHeader(viewModel: viewModel)
            Divider()
            ShelfItemsRow(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShelfBackground())
        .sheet(item: $viewModel.editingItem) { item in
            EditItemSheet(
                item: item,
                onCancel: { viewModel.editingItem = nil },
                onSave: { viewModel.commitEdit($0) }
            )
        }
    }
}

private struct ShelfHeader: View {
    @Bindable var viewModel: ShelfViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            ShelfTabs(viewModel: viewModel)
            Spacer(minLength: 12)
            if !viewModel.query.isEmpty {
                ForEach(ShelfScope.allCases, id: \.self) { scope in
                    ScopeChip(title: scope.title, isOn: viewModel.scope == scope) {
                        viewModel.scope = scope
                    }
                }
                .transition(.opacity)
            }
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .frame(maxWidth: 220)
        }
        .padding(.horizontal, Tokens.shelfPadding)
        .padding(.vertical, 8)
        .animation(.easeOut(duration: 0.12), value: viewModel.query.isEmpty)
        .onAppear { searchFocused = true }
    }
}

/// Left-hand pill row: History, then pinboards, then Add Pinboard.
private struct ShelfTabs: View {
    @Bindable var viewModel: ShelfViewModel
    @State private var createPresented = false
    @State private var renamingPinboard: Pinboard?
    @State private var dropTargetedPinboardID: Int64?

    var body: some View {
        HStack(spacing: 4) {
            TabPill(
                label: "History",
                symbol: "clock",
                isSelected: viewModel.tab == .history,
                action: { viewModel.tab = .history }
            )
            ForEach(viewModel.pinboards, id: \.id) { pinboard in
                TabPill(
                    label: pinboard.name,
                    symbol: pinboard.symbol,
                    isSelected: pinboard.id.map { viewModel.tab == .pinboard($0) } ?? false,
                    isDropTargeted: pinboard.id != nil && dropTargetedPinboardID == pinboard.id,
                    action: {
                        guard let id = pinboard.id else { return }
                        viewModel.tab = .pinboard(id)
                    }
                )
                .contextMenu {
                    // "Rename…" opens PinboardEditPopover in rename mode, which edits both
                    // name and symbol in one place — no separate "Change Symbol…" item.
                    Button("Rename…") { renamingPinboard = pinboard }
                    Button("Delete Pinboard", role: .destructive) { confirmDelete(pinboard) }
                }
                .popover(isPresented: Binding(
                    get: { pinboard.id != nil && renamingPinboard?.id == pinboard.id },
                    set: { if !$0 { renamingPinboard = nil } }
                )) {
                    PinboardEditPopover(mode: .rename(pinboard)) { name, symbol in
                        if let id = pinboard.id {
                            viewModel.renamePinboard(id: id, to: name)
                            viewModel.setPinboardSymbol(id: id, symbol)
                        }
                        renamingPinboard = nil
                    }
                }
                .onDrop(of: [UTType.copyItem], isTargeted: Binding(
                    get: { pinboard.id != nil && dropTargetedPinboardID == pinboard.id },
                    set: { dropTargetedPinboardID = $0 ? pinboard.id : nil }
                )) { providers in
                    guard let provider = providers.first else { return false }
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.copyItem.identifier) { data, _ in
                        guard let data, let uuid = String(data: data, encoding: .utf8) else { return }
                        DispatchQueue.main.async {
                            viewModel.dropItem(uuid: uuid, toPinboard: pinboard)
                        }
                    }
                    return true
                }
            }
            Button {
                createPresented = true
            } label: {
                Image(systemName: "plus")
                    .font(Tokens.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add Pinboard")
            .popover(isPresented: $createPresented) {
                PinboardEditPopover(mode: .create) { name, symbol in
                    viewModel.createPinboard(name: name, symbol: symbol)
                }
            }
        }
    }

    /// Matches the existing `NSAlert` confirm pattern (`AppDelegate.clearHistory`), with
    /// the alert's window bumped to the shelf panel's own `.statusBar` level — otherwise
    /// the alert would render behind the always-on-top, non-activating shelf panel.
    private func confirmDelete(_ pinboard: Pinboard) {
        guard let id = pinboard.id else { return }
        let alert = NSAlert()
        alert.messageText = "Delete pinboard \(pinboard.name)?"
        alert.informativeText = "Items stay in your history."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.window.level = .statusBar
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            viewModel.deletePinboard(id: id)
        }
    }
}

private struct TabPill: View {
    let label: String
    let symbol: String
    let isSelected: Bool
    var isDropTargeted: Bool = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .font(Tokens.caption)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(backgroundFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isDropTargeted ? Color.accentColor : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var backgroundFill: Color {
        if isDropTargeted { return Color.accentColor.opacity(0.16) }
        if isSelected { return Color.primary.opacity(0.08) }
        return isHovering ? Color.primary.opacity(0.05) : .clear
    }
}

private struct ScopeChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Tokens.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.18) : .clear))
                .overlay(Capsule().stroke(isOn ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct ShelfItemsRow: View {
    @Bindable var viewModel: ShelfViewModel

    private var currentPinboardID: Int64? {
        if case .pinboard(let id) = viewModel.tab { return id }
        return nil
    }

    var body: some View {
        if viewModel.items.isEmpty {
            ShelfEmptyState(viewModel: viewModel)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Tokens.cardGap) {
                        ForEach(viewModel.items, id: \.uuid) { item in
                            ItemCardView(
                                item: item,
                                isSelected: viewModel.isSelected(item),
                                store: viewModel.store,
                                pinboards: viewModel.pinboards,
                                currentPinboardID: currentPinboardID,
                                onClick: { modifiers in viewModel.handleCardClick(item, modifiers: modifiers) },
                                onPaste: { viewModel.requestPaste(item, plain: false) },
                                onPastePlain: { viewModel.requestPaste(item, plain: true) },
                                onEdit: { viewModel.beginEdit() },
                                onToggleFavorite: { viewModel.toggleFavorite(item) },
                                onAddToPinboard: { id in viewModel.addItem(item, toPinboard: id) },
                                onRemoveFromPinboard: {
                                    if let currentPinboardID {
                                        viewModel.removeItem(item, fromPinboard: currentPinboardID)
                                    }
                                },
                                onDelete: { viewModel.delete(item) },
                                dragProvider: { viewModel.dragProvider(for: item) }
                            )
                            .id(item.uuid)
                            .popover(isPresented: Binding(
                                get: { viewModel.isSelected(item) && item.uuid == viewModel.selection.primary && viewModel.previewShown },
                                set: { viewModel.previewShown = $0 }
                            )) {
                                PreviewPane(item: item, store: viewModel.store)
                            }
                        }
                    }
                    .padding(.horizontal, Tokens.shelfPadding)
                    .padding(.vertical, 16)
                }
                .onChange(of: viewModel.selection.primary) { _, newPrimary in
                    if let newPrimary {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(newPrimary, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

/// Empty state for the items row, tailored to the active tab and search state.
private struct ShelfEmptyState: View {
    let viewModel: ShelfViewModel

    private var symbolName: String {
        switch viewModel.tab {
        case .history:
            return "doc.on.clipboard"
        case .pinboard(let id):
            return viewModel.pinboards.first(where: { $0.id == id })?.symbol ?? "pin"
        }
    }

    private var headline: String {
        if !viewModel.query.isEmpty {
            return "No matches for \"\(viewModel.query)\""
        }
        switch viewModel.tab {
        case .history: return "Copy something to get started"
        case .pinboard: return "Nothing pinned yet"
        }
    }

    private var caption: String? {
        guard viewModel.query.isEmpty, case .pinboard = viewModel.tab else { return nil }
        return "Drag a card here or use Add to Pinboard"
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(headline)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if let caption {
                Text(caption)
                    .font(Tokens.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ShelfBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
