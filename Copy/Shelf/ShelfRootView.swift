import SwiftUI
import CopyCore
import AppKit
import UniformTypeIdentifiers

struct ShelfRootView: View {
    @Bindable var viewModel: ShelfViewModel
    @State private var permissionBannerDismissed = false
    /// Persisted so the keyboard legend, once dismissed, stays gone. Read once here;
    /// `dismissLegend()` writes it back. Defaults to shown (false) for new users.
    @State private var legendDismissed = UserDefaults.standard.bool(forKey: Self.legendDismissedKey)

    private static let legendDismissedKey = "shelfKeyboardLegendDismissed"

    /// The legend teaches the keyboard path, so it earns its slim strip when there are
    /// cards to act on and the shelf is at full height (compact mode trades this away for
    /// density). Holding ⌘ re-summons it even after it's been dismissed.
    private var showsLegend: Bool {
        guard !viewModel.items.isEmpty, !viewModel.settings.compactShelf else { return false }
        return !legendDismissed || viewModel.commandHeld
    }

    private func dismissLegend() {
        UserDefaults.standard.set(true, forKey: Self.legendDismissedKey)
        withAnimation(.easeOut(duration: 0.15)) { legendDismissed = true }
    }

    /// Reads `viewModel.accessibilityTrusted` rather than checking `AXIsProcessTrusted()`
    /// itself, since the shelf panel + this view are created once and reused for the
    /// app's lifetime — a one-time `.onAppear` read here would only ever reflect
    /// whatever was true the very first time the shelf ever appeared. `AppCoordinator`
    /// refreshes that state on every shelf open (see `ShelfViewModel.refreshPermissionState()`),
    /// so once access is granted, the next open simply stops showing the banner.
    private var showsPermissionBanner: Bool {
        !viewModel.accessibilityTrusted && !permissionBannerDismissed
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsPermissionBanner {
                PermissionBanner(onDismiss: { permissionBannerDismissed = true })
            }
            ShelfHeader(viewModel: viewModel)
            Divider()
            ShelfItemsRow(viewModel: viewModel)
            if showsLegend {
                KeyboardLegend(onDismiss: dismissLegend)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(corners: .top(12))
        // Pro-dark: force the marketing electric-blue accent regardless of the system
        // accent color. The forced dark appearance itself is set on the panel window in
        // `ShelfPanelController`, which cascades to this hosted content.
        .tint(viewModel.settings.shelfProDark ? Tokens.electricBlue : nil)
        .sheet(item: $viewModel.editingItem) { item in
            EditItemSheet(
                item: item,
                store: viewModel.store,
                onCancel: { viewModel.editingItem = nil },
                onSave: { viewModel.commitEdit(attributed: $0) }
            )
        }
        .sheet(isPresented: $viewModel.creatingItem) {
            CreateItemSheet(
                onCancel: { viewModel.creatingItem = false },
                onCreate: { text, title in viewModel.commitCreate(text: text, title: title) }
            )
        }
        .sheet(item: $viewModel.adjustingColorItem) { item in
            ColorAdjustSheet(
                item: item,
                onCancel: { viewModel.adjustingColorItem = nil },
                onCopy: { viewModel.commitAdjustColor($0) }
            )
        }
        .sheet(isPresented: $viewModel.showingTips) {
            TipsSheet(onDone: { viewModel.showingTips = false })
        }
    }
}

/// Slim, quiet strip (no colored fill — just an SF Symbol and text on the shelf's
/// existing material) shown while Accessibility isn't granted, since without it
/// `AppCoordinator.pasteFromShelf` can only place the item on the clipboard rather
/// than actually paste it into the frontmost app.
private struct PermissionBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Text("Copy needs Accessibility access to paste.")
                    .font(Tokens.caption)
                    .foregroundStyle(.secondary)
                Button("Open Settings") { openAccessibilitySettings() }
                    .buttonStyle(.link)
                    .font(Tokens.caption)
                Spacer(minLength: 8)
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(Tokens.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, Tokens.shelfPadding)
            .padding(.vertical, 6)
            Divider()
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct ShelfHeader: View {
    @Bindable var viewModel: ShelfViewModel
    @FocusState private var searchFocused: Bool

    /// Quiet scope hint: on a pinboard tab, the search field's placeholder names the
    /// board so the user knows a query only searches its members, not all of history.
    /// Falls back to the global "Search" placeholder on History, and if the tab's
    /// pinboard can't be resolved (e.g. mid-delete).
    private var searchPlaceholder: String {
        if case .pinboard(let id) = viewModel.tab,
           let name = viewModel.pinboards.first(where: { $0.id == id })?.name {
            return "Search \(name)"
        }
        return "Search"
    }

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
                TextField(searchPlaceholder, text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .frame(maxWidth: 220)
            DrawerMenu(viewModel: viewModel)
        }
        .padding(.horizontal, Tokens.shelfPadding)
        .padding(.vertical, 8)
        .animation(.easeOut(duration: 0.12), value: viewModel.query.isEmpty)
        .onAppear { searchFocused = true }
    }
}

/// The shelf's own "more" control — a discreet ellipsis button mirroring every
/// status-menu action, so the app is fully usable with the menu bar icon hidden
/// (`SettingsStore.hideMenuBarIcon`). Deliberately quiet (borderless, no chevron,
/// secondary tint) rather than a toolbar, to match the shelf's existing icon-button
/// language (e.g. the "Add Pinboard" `+` in `ShelfTabs`).
private struct DrawerMenu: View {
    let viewModel: ShelfViewModel
    @State private var target = MenuActionTarget()

    var body: some View {
        // A plain Button that pops an NSMenu, rather than a SwiftUI `Menu`: the latter's
        // `.borderlessButton` style only made the glyph pixels clickable, so the ⋯ was
        // extremely hard to hit. A Button's frame + `contentShape` is a guaranteed target.
        Button(action: showMenu) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More")
    }

    private func showMenu() {
        let menu = NSMenu()
        func add(_ title: String, checked: Bool = false, _ action: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: #selector(MenuActionTarget.fire(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = MenuAction(run: action)
            item.state = checked ? .on : .off
            menu.addItem(item)
        }
        add("New Item…") { viewModel.onNewItem?() }
        add("Paste Stack", checked: viewModel.isPasteStackOn) { viewModel.onTogglePasteStack?() }
        add(viewModel.isPrivacyModeOn ? "Resume Monitoring" : "Pause Monitoring") { viewModel.onTogglePrivacyMode?() }
        menu.addItem(.separator())
        add("Clear History…") { viewModel.onClearHistory?() }
        add("Export…") { viewModel.onExportHistory?() }
        add("Import…") { viewModel.onImportHistory?() }
        menu.addItem(.separator())
        add("Keyboard & Tips…") { viewModel.showingTips = true }
        add("Settings…") { viewModel.onOpenSettings?() }
        add("Check for Updates…") { viewModel.onCheckForUpdates?() }
        menu.addItem(.separator())
        add("Quit Copy") { viewModel.onQuit?() }

        guard let window = NSApp.keyWindow, let content = window.contentView else { return }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let viewPoint = content.convert(windowPoint, from: nil)
        menu.popUp(positioning: nil, at: viewPoint, in: content)
    }
}

/// Wraps a Swift closure so it can ride an `NSMenuItem`'s `representedObject` and be
/// invoked by `MenuActionTarget` — AppKit menu items are selector-based, not closure-based.
private final class MenuAction {
    let run: () -> Void
    init(run: @escaping () -> Void) { self.run = run }
}

private final class MenuActionTarget: NSObject {
    @objc func fire(_ sender: NSMenuItem) {
        (sender.representedObject as? MenuAction)?.run()
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
                shortcutHint: viewModel.commandHeld ? "1" : nil,
                action: { viewModel.tab = .history }
            )
            ForEach(Array(viewModel.pinboards.enumerated()), id: \.element.id) { offset, pinboard in
                TabPill(
                    label: pinboard.name,
                    symbol: pinboard.symbol,
                    emoji: pinboard.emoji,
                    tint: pinboard.tint,
                    showsSymbol: false,
                    isSelected: pinboard.id.map { viewModel.tab == .pinboard($0) } ?? false,
                    isDropTargeted: pinboard.id != nil && dropTargetedPinboardID == pinboard.id,
                    // ⌘1 is History, so pinboards start at ⌘2; only the first eight get a
                    // hint (⌘9 is the ceiling of the number-key routing).
                    shortcutHint: (viewModel.commandHeld && offset + 2 <= 9) ? "\(offset + 2)" : nil,
                    action: {
                        guard let id = pinboard.id else { return }
                        viewModel.tab = .pinboard(id)
                    }
                )
                .contextMenu {
                    // "Rename…" opens PinboardEditPopover in rename mode, which edits
                    // name, symbol, emoji, and color in one place.
                    Button("Rename…") { renamingPinboard = pinboard }
                    Button("Delete Pinboard", role: .destructive) { confirmDelete(pinboard) }
                }
                .popover(isPresented: Binding(
                    get: { pinboard.id != nil && renamingPinboard?.id == pinboard.id },
                    set: { if !$0 { renamingPinboard = nil } }
                )) {
                    PinboardEditPopover(mode: .rename(pinboard)) { name, symbol, emoji, tint in
                        if let id = pinboard.id {
                            viewModel.renamePinboard(id: id, to: name)
                            viewModel.setPinboardSymbol(id: id, symbol)
                            viewModel.setPinboardEmoji(id: id, emoji)
                            viewModel.setPinboardTint(id: id, tint)
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
                        guard let data, let payload = String(data: data, encoding: .utf8) else { return }
                        // Single-card drags carry one uuid; multi-selection drags carry
                        // every selected uuid newline-joined (see `ShelfViewModel.multiDragProvider()`).
                        let uuids = payload.split(separator: "\n").map(String.init)
                        guard !uuids.isEmpty else { return }
                        DispatchQueue.main.async {
                            viewModel.dropItems(uuids: uuids, toPinboard: pinboard)
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
                    // A comfortable, fully-hittable target (the glyph alone is tiny).
                    .frame(width: 34, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add Pinboard")
            .popover(isPresented: $createPresented) {
                PinboardEditPopover(mode: .create) { name, symbol, emoji, tint in
                    viewModel.createPinboard(name: name, symbol: symbol, emoji: emoji, tint: tint)
                }
            }
        }
        .onChange(of: createPresented) { _, isPresented in
            viewModel.pinboardPopoverShown = isPresented || renamingPinboard != nil
        }
        .onChange(of: renamingPinboard) { _, newValue in
            viewModel.pinboardPopoverShown = createPresented || newValue != nil
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
    /// A user-chosen emoji shown in place of the SF Symbol, when set. `nil`/untinted
    /// pinboards (and the History tab) render exactly as before this feature.
    var emoji: String? = nil
    /// A user-chosen hex color (e.g. "FF3B30"); empty means no color identity.
    var tint: String = ""
    /// Whether to draw the SF Symbol when no emoji is set. History uses it (a clock);
    /// pinboards don't — their identity is the color dot and optional emoji.
    var showsSymbol: Bool = true
    let isSelected: Bool
    var isDropTargeted: Bool = false
    /// The ⌘-number that jumps to this tab (e.g. "1"), shown as a badge while ⌘ is held.
    var shortcutHint: String? = nil
    let action: () -> Void
    @State private var isHovering = false

    private var tintColor: Color? {
        tint.isEmpty ? nil : Tokens.color(fromHex: tint)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let emoji, !emoji.isEmpty {
                    Text(emoji)
                } else if showsSymbol {
                    Image(systemName: symbol)
                }
                Text(label)
                if let tintColor {
                    Circle()
                        .fill(tintColor)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                if let shortcutHint {
                    Text("⌘\(shortcutHint)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color(nsColor: .quaternaryLabelColor).opacity(0.6)))
                        .accessibilityHidden(true)
                }
            }
            .font(Tokens.caption)
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
        if isSelected {
            if let tintColor { return tintColor.opacity(0.18) }
            return Color.primary.opacity(0.08)
        }
        return isHovering ? Color.primary.opacity(0.05) : .clear
    }
}

private struct ScopeChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Tokens.caption)
                .foregroundStyle(isOn ? .primary : .secondary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(backgroundFill)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var backgroundFill: Color {
        if isOn { return Color.primary.opacity(0.08) }
        return isHovering ? Color.primary.opacity(0.05) : .clear
    }
}

private struct ShelfItemsRow: View {
    @Bindable var viewModel: ShelfViewModel

    private var currentPinboardID: Int64? {
        if case .pinboard(let id) = viewModel.tab { return id }
        return nil
    }

    /// Read straight from `SettingsStore` (both it and `ShelfViewModel` are
    /// `@Observable`), so toggling "Shelf Size" in Settings re-renders this row
    /// immediately — no separate change-hook plumbing needed on the SwiftUI side.
    private var compact: Bool { viewModel.settings.compactShelf }

    var body: some View {
        if viewModel.items.isEmpty {
            ShelfEmptyState(viewModel: viewModel)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Tokens.cardGap(compact: compact)) {
                        ForEach(viewModel.items, id: \.uuid) { item in
                            ItemCardView(
                                item: item,
                                isSelected: viewModel.isSelected(item),
                                isInlineRenaming: viewModel.inlineRenamingItemID == item.id,
                                store: viewModel.store,
                                pinboards: viewModel.pinboards,
                                currentPinboardID: currentPinboardID,
                                compact: compact,
                                searchQuery: viewModel.query,
                                onClick: { modifiers in viewModel.handleCardClick(item, modifiers: modifiers) },
                                onHoverChanged: { hovering in
                                    if hovering {
                                        viewModel.hoveredItemID = item.uuid
                                    } else if viewModel.hoveredItemID == item.uuid {
                                        viewModel.hoveredItemID = nil
                                    }
                                },
                                onPaste: { viewModel.requestPaste(item, plain: false) },
                                onPastePlain: { viewModel.requestPaste(item, plain: true) },
                                onEdit: { viewModel.beginEdit(item) },
                                onAdjustColor: { viewModel.beginAdjustColor(item) },
                                onBeginInlineRename: { viewModel.beginInlineRename(item) },
                                onCommitInlineRename: { viewModel.commitInlineRename(item, to: $0) },
                                onCancelInlineRename: { viewModel.cancelInlineRename() },
                                onToggleFavorite: { viewModel.toggleFavorite(item) },
                                onAddToPinboard: { id in viewModel.addItem(item, toPinboard: id) },
                                onRemoveFromPinboard: {
                                    if let currentPinboardID {
                                        viewModel.removeItem(item, fromPinboard: currentPinboardID)
                                    }
                                },
                                onAddToPasteStack: { viewModel.addToPasteStack(item) },
                                onCopyText: { viewModel.copyText(item) },
                                onQuickLook: { viewModel.quickLook(item) },
                                onOpen: { viewModel.open(item) },
                                onRotate: { viewModel.rotateImage(item, clockwise: $0) },
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
                    .padding(.horizontal, Tokens.shelfPadding(compact: compact))
                    .padding(.vertical, compact ? 10 : 16)
                    // Make the whole row (including the gaps between cards) hit-testable so
                    // a scroll wheel over a gap still scrolls the shelf instead of passing
                    // through to the panel behind. No tap gesture lives on the row, so this
                    // never captures clicks meant for the cards.
                    .contentShape(Rectangle())
                }
                .onChange(of: viewModel.selection.primary) { _, newPrimary in
                    if let newPrimary {
                        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                            proxy.scrollTo(newPrimary, anchor: .center)
                        } else {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(newPrimary, anchor: .center)
                            }
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
            return "square.on.square"
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

    /// True only on the empty History tab with no active search: the genuine "nothing
    /// captured yet" moment, where a short first-run primer earns its space. Search and
    /// pinboard empties stay minimal.
    private var isFirstRun: Bool {
        guard viewModel.query.isEmpty else { return false }
        if case .history = viewModel.tab { return true }
        return false
    }

    var body: some View {
        VStack(spacing: isFirstRun ? 10 : 6) {
            Image(systemName: symbolName)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text(headline)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if isFirstRun {
                Text("Text, images, links, files, and colors all land here automatically.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 14) {
                    KeyHint(key: "⇧⌘V", label: "Open Copy")
                    KeyHint(key: "↩", label: "Paste")
                    KeyHint(key: "Space", label: "Preview")
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A slim, dismissible strip along the shelf's bottom that teaches the core keyboard
/// path. Sized to fit the standard shelf's spare vertical space below the cards; hidden
/// in compact mode and once dismissed (see `ShelfRootView.showsLegend`).
private struct KeyboardLegend: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            KeyHint(key: "↩", label: "Paste")
            KeyHint(key: "Space", label: "Preview")
            KeyHint(key: "⌥↩", label: "Plain text")
            KeyHint(key: "⌘⌫", label: "Delete")
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide keyboard tips")
        }
        .padding(.horizontal, Tokens.shelfPadding)
        .padding(.top, 4)
        .padding(.bottom, 11)
    }
}
