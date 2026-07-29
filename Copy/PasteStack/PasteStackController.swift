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

    init(model: PasteStackModel) {
        self.model = model
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

    /// (Re)shows the palette at the top-right of the mouse's screen, sized to fit the
    /// current queue (capped at `maxHeight`). Safe to call while already visible — it
    /// just repositions/resizes in place, which is how the panel stays fit to content
    /// as items are added, removed, or cleared (see `PasteStackView.onContentChange`).
    func show() {
        // Drop any queued uuid that's gone missing (deleted/pruned) since being
        // queued. `PasteStackModel.items()` is a pure read used from SwiftUI bodies,
        // so this explicit event point — the palette becoming visible — is where that
        // bookkeeping actually happens.
        model.reconcile()

        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main else { return }

        let panel = self.panel ?? makePanel()
        self.panel = panel

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

    private func computeHeight() -> CGFloat {
        let count = model.items().count
        let header: CGFloat = 34
        let dividers: CGFloat = 2
        let footer: CGFloat = 76
        let content: CGFloat = count == 0 ? 90 : CGFloat(count) * 30
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
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: PasteStackView(
            model: model,
            onClose: { [weak model] in model?.isActive = false },
            onContentChange: { [weak self] in self?.show() }
        ))
        return panel
    }
}
