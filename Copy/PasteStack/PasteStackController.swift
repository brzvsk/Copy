import AppKit
import SwiftUI

/// Floating Paste Stack palette. Unlike `ShelfPanelController`, this panel must never
/// activate the app or become key — the whole point of the stack is that plain ⌘V
/// keeps going to the frontmost app while the palette floats on top (Task 7's CGEvent
/// tap intercepts that keystroke). So `show()` only calls `orderFrontRegardless()`,
/// never `makeKeyAndOrderFront`/`NSApp.activate`. `.nonactivatingPanel` panels still
/// deliver mouse events (button clicks, list drag-reorder) without becoming key or
/// stealing focus, which is what makes the palette interactive despite that.
@MainActor
final class PasteStackController {
    static let width: CGFloat = 280
    static let maxHeight: CGFloat = 420
    static let inset: CGFloat = 16

    private let model: PasteStackModel
    private var panel: KeyablePanel?
    private var hideDuringScreenSharing: Bool
    private var proDark: Bool

    init(model: PasteStackModel, hideDuringScreenSharing: Bool, proDark: Bool) {
        self.model = model
        self.hideDuringScreenSharing = hideDuringScreenSharing
        self.proDark = proDark
    }

    /// Pushed live by `AppCoordinator` via `SettingsStore.onShelfProDarkChange`. Forces
    /// the palette (and its hosted SwiftUI content) to a dark appearance so it matches
    /// the pro-dark shelf; `nil` returns to following the system, mirroring
    /// `ShelfPanelController.setProDark`. The accent tint is baked into the hosted view at
    /// `makePanel` time, so when the (cached) palette isn't on screen we drop it and let
    /// the next `show()` rebuild it with both the appearance and the tint from the new
    /// value; when it is on screen we can only update the window appearance live (the tint
    /// refreshes on its next open).
    func setProDark(_ on: Bool) {
        proDark = on
        if let panel, panel.isVisible {
            panel.appearance = on ? NSAppearance(named: .darkAqua) : nil
        } else {
            panel?.orderOut(nil)
            panel = nil
        }
    }

    /// Applied at panel creation and pushed live here when the setting changes
    /// (`AppCoordinator` wires `SettingsStore.onHideDuringScreenSharingChange`). `.none`
    /// excludes the palette from screen recordings/captures/shares; `.readOnly` is
    /// AppKit's normal default (content visible, not modifiable by other processes).
    func setHideDuringScreenSharing(_ hide: Bool) {
        hideDuringScreenSharing = hide
        panel?.sharingType = hide ? .none : .readOnly
        panel?.childWindowSharingType = hide ? .none : .readOnly
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Single entry point for palette visibility, wired to `model.onActiveChange` by
    /// `AppCoordinator`. Also fine to call directly (e.g. from `show()`'s own
    /// content-change hook) since both `show()` and `hide()` are idempotent.
    func syncVisibility(to isActive: Bool) {
        if isActive {
            show()
        } else {
            hide()
        }
    }

    /// Shows the palette at the top-right of the mouse's screen, sized to fit the
    /// current queue (capped at `maxHeight`). Only positions fresh when the panel isn't
    /// already visible — once the user has moved/is looking at the palette, content
    /// changes must not teleport it back to the corner; that's what `resizeToFit()`
    /// (wired to `PasteStackView.onContentChange`) is for.
    func show() {
        // Drop any queued uuid that's gone missing (deleted/pruned) since being
        // queued. `PasteStackModel.items()` is a pure read used from SwiftUI bodies,
        // so this explicit event point — the palette becoming visible — is where that
        // bookkeeping actually happens.
        model.reconcile()

        let panel = self.panel ?? makePanel()
        self.panel = panel

        guard !panel.isVisible else {
            resizeToFit()
            return
        }

        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main else { return }

        let height = computeHeight()
        let frame = NSRect(
            x: screen.visibleFrame.maxX - Self.width - Self.inset,
            y: screen.visibleFrame.maxY - height - Self.inset,
            width: Self.width,
            height: height
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Re-fits the palette's height to the current queue while keeping its current
    /// on-screen position, anchored at the current top edge. Called from
    /// `PasteStackView.onContentChange` (items added/removed/reordered) so the palette
    /// doesn't jump back to the top-right corner on every copy while the stack is
    /// active — only `show()`'s fresh-activation path positions there. AppKit frames
    /// are bottom-left-anchored, so holding the top edge fixed while the height changes
    /// means recomputing the origin's y: `newOriginY = currentTopY - newHeight`.
    private func resizeToFit() {
        guard let panel, panel.isVisible else { return }
        let current = panel.frame
        let currentTopY = current.origin.y + current.height
        let newHeight = computeHeight()
        let newFrame = NSRect(
            x: current.origin.x,
            y: currentTopY - newHeight,
            width: current.width,
            height: newHeight
        )
        panel.setFrame(newFrame, display: true)
    }

    private func computeHeight() -> CGFloat {
        let count = model.items().count
        let header: CGFloat = 34
        // Empty palette has no footer (order picker + Clear are hidden), so it's just the
        // header, a divider, and the compact empty state.
        if count == 0 {
            return header + 1 + 120
        }
        let dividers: CGFloat = 2
        let footer: CGFloat = 82
        let content: CGFloat = CGFloat(count) * PasteStackView.rowHeight + 8
        return min(max(header + dividers + footer + content, 180), Self.maxHeight)
    }

    private func makePanel() -> KeyablePanel {
        let panel = KeyablePanel(contentRect: .zero,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = proDark ? NSAppearance(named: .darkAqua) : nil
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isFloatingPanel = true
        // Off: the window is dragged explicitly from the header (WindowDragArea →
        // performDrag), so dragging a list row is free to reorder it. See PasteStackView.
        panel.isMovableByWindowBackground = false
        panel.sharingType = hideDuringScreenSharing ? .none : .readOnly
        panel.childWindowSharingType = hideDuringScreenSharing ? .none : .readOnly

        // The panel's contentView is a real NSVisualEffectView, not the SwiftUI
        // `.glassEffect`: on macOS 26 that effect has no backing NSView, so the empty areas
        // of this non-key panel let clicks fall through to the app behind. A visual-effect
        // view is a real view that absorbs every click over its frame while still reading as
        // dark glass, consistent with the shelf. The SwiftUI content sits on top of it.
        let hosting = NSHostingView(rootView: PasteStackView(
            model: model,
            onClose: { [weak model] in model?.isActive = false },
            onContentChange: { [weak self] in self?.resizeToFit() }
        )
        .tint(proDark ? Tokens.electricBlue : nil))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        // The material view (a real NSView) makes every pixel non-transparent, so the
        // window server stops passing clicks through the panel to the app behind — the
        // actual root cause of the click-through under macOS 26's backing-view-less glass.
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.translatesAutoresizingMaskIntoConstraints = false

        // A plain container as the contentView, with the material behind and the SwiftUI
        // content in front, both pinned to it. Pinning the hosting view to a plain view
        // (not to the material view itself) keeps its layout correct — no clipped header.
        let container = NSView()
        container.wantsLayer = true
        container.addSubview(effect)
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effect.topAnchor.constraint(equalTo: container.topAnchor),
            effect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        panel.contentView = container
        panel.hasShadow = true
        return panel
    }
}
