import AppKit

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// SwiftUI's `.popover()` presents its content in a separate `NSWindow` attached to
    /// this one via `addChildWindow` — a different window than the panel itself, so
    /// merely setting the panel's own `sharingType` doesn't exclude it from capture.
    /// `ShelfPanelController` keeps this
    /// in sync with its own `sharingType` policy; every child window attached from then
    /// on inherits it here, before `super.addChildWindow` orders it on screen.
    var childWindowSharingType: NSWindow.SharingType = .readOnly

    override func addChildWindow(_ childWin: NSWindow, ordered place: NSWindow.OrderingMode) {
        childWin.sharingType = childWindowSharingType
        super.addChildWindow(childWin, ordered: place)
    }
}

@MainActor
final class ShelfPanelController: NSObject, NSWindowDelegate {
    static let shelfHeight: CGFloat = 352
    /// Keeps the shelf visually detached from the screen edges. The same inset on both
    /// horizontal sides makes the panel read as one floating surface, while the bottom
    /// gap leaves room for its newly rounded lower corners and shadow.
    static let shelfInset: CGFloat = 12
    /// Panel height while `SettingsStore.compactShelf` is on, sized to `Tokens.compactCardHeight`
    /// plus the same header/divider/padding chrome `shelfHeight` allows for above the
    /// (shorter) card row. `ShelfHeader` isn't shortened in compact mode, so the fixed
    /// chrome above the card row (header + divider + `ShelfItemsRow`'s own vertical
    /// padding) is ~229pt; 232 left only ~3pt of margin before cards could clip against
    /// the panel's bottom edge, so this carries the same ~7% margin `shelfHeight` gives
    /// the standard card row.
    static let compactShelfHeight: CGFloat = 244

    var onKeyEvent: ((NSEvent) -> Bool)?
    /// Called on every modifier-key change while the shelf is open (⌘-hold hints).
    var onFlagsChanged: ((NSEvent) -> Void)?
    /// Called once when a force-click (pressure stage 2) begins over the shelf.
    var onForceClick: (() -> Void)?
    private var lastPressureStage = 0
    var onDidHide: (() -> Void)?

    private let makeContent: () -> NSView
    private var panel: KeyablePanel?
    private var modalPanel: KeyablePanel?
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?
    /// Guards the animated close until the panel is actually ordered out.
    private var isHiding = false
    /// Actions requested while the same close is in flight. They must wait for `orderOut`
    /// and focus restoration just like the action that initiated the close.
    private var pendingHideCompletions: [() -> Void] = []
    /// Bumped by both `show()` and each `hide()` so a stale close animation's completion
    /// handler doesn't order the panel out after a newer show/hide has superseded it.
    private var closeToken = 0
    private var hideDuringScreenSharing: Bool
    private var compactShelf: Bool
    private var theme: ShelfTheme

    init(hideDuringScreenSharing: Bool, compactShelf: Bool, theme: ShelfTheme, makeContent: @escaping () -> NSView) {
        self.hideDuringScreenSharing = hideDuringScreenSharing
        self.compactShelf = compactShelf
        self.theme = theme
        self.makeContent = makeContent
    }

    /// Pushed live by `AppCoordinator` via `SettingsStore.onShelfThemeChange`.
    func setTheme(_ theme: ShelfTheme) {
        self.theme = theme
        panel?.appearance = theme.appearance
        modalPanel?.appearance = theme.appearance
    }

    private var currentShelfHeight: CGFloat {
        compactShelf ? Self.compactShelfHeight : Self.shelfHeight
    }

    private func shelfFrame(in visibleFrame: NSRect) -> NSRect {
        NSRect(x: visibleFrame.minX + Self.shelfInset,
               y: visibleFrame.minY + Self.shelfInset,
               width: visibleFrame.width - (Self.shelfInset * 2),
               height: currentShelfHeight)
    }

    /// Places the shelf immediately beyond the same bottom edge it is attached to, so
    /// its transition has a clear spatial origin instead of looking like a dissolve.
    private func frameBelowScreen(_ frame: NSRect, visibleFrame: NSRect) -> NSRect {
        frame.offsetBy(dx: 0, dy: visibleFrame.minY - frame.maxY)
    }

    /// Applied at panel creation and pushed live here when the setting changes
    /// (`AppCoordinator` wires `SettingsStore.onHideDuringScreenSharingChange`). `.none`
    /// excludes the panel from screen recordings/captures/shares; `.readOnly` is
    /// AppKit's normal default (content visible, not modifiable by other processes).
    func setHideDuringScreenSharing(_ hide: Bool) {
        hideDuringScreenSharing = hide
        panel?.sharingType = hide ? .none : .readOnly
        panel?.childWindowSharingType = hide ? .none : .readOnly
    }

    /// Pushed live by `AppCoordinator` via `SettingsStore.onCompactShelfChange`. Updates
    /// the height used on the next `show()` and, if the panel is already visible,
    /// resizes it immediately so toggling the setting doesn't need a close/reopen —
    /// mirrors `setHideDuringScreenSharing`'s live-update shape above.
    func setCompactShelf(_ compact: Bool) {
        compactShelf = compact
        guard isVisible, let panel,
              let screen = NSScreen.screens.first(where: {
                  NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
              }) ?? NSScreen.main else { return }
        let frame = shelfFrame(in: screen.visibleFrame)
        panel.setFrame(frame, display: true)
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide(restoreFocus: true) : show()
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main else { return }

        let frame = shelfFrame(in: screen.visibleFrame)
        let panel = self.panel ?? makePanel()
        self.panel = panel

        // Cancel any in-flight close: invalidate its completion token and drop the guard so
        // re-summoning mid-close animates straight back in.
        closeToken += 1
        isHiding = false

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(reduceMotion ? frame : frameBelowScreen(frame, visibleFrame: screen.visibleFrame), display: false)
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.13
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.22, 1, 0.36, 1
                )
                panel.animator().setFrame(frame, display: true)
            }
        }
        installKeyMonitor()
        // The shelf opens in browse mode: keep the search field from auto-becoming first
        // responder when the panel keys up (AppKit picks the first text field otherwise).
        // Clear it now and again after SwiftUI's first layout pass, which can set it late.
        // Type-to-search (the global key monitor) still works with nothing focused.
        panel.makeFirstResponder(nil)
        DispatchQueue.main.async { [weak panel] in panel?.makeFirstResponder(nil) }
    }

    func hide(restoreFocus: Bool, completion: (() -> Void)? = nil) {
        guard let panel, isVisible else {
            completion?()
            return
        }
        if let completion {
            pendingHideCompletions.append(completion)
        }
        // A repeated action during the close joins the current transition instead of
        // being dropped or running before the destination app regains focus.
        guard !isHiding else { return }
        // Keep the non-activating panel key until it is fully out. On macOS 26 the shelf
        // is live Liquid Glass; returning key focus while that glass is still visible
        // changes its sampled backdrop mid-transition and produces a one-frame flash.
        isHiding = true
        removeKeyMonitor()

        // Mirror the entrance direction and move the whole shelf beyond the bottom edge.
        // Reduce Motion skips straight to orderOut.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            finishHide(panel, restoreFocus: restoreFocus)
            return
        }

        closeToken += 1
        let token = closeToken
        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let destination = visibleFrame.map { frameBelowScreen(panel.frame, visibleFrame: $0) }
            ?? panel.frame.offsetBy(dx: 0, dy: -(panel.frame.height + Self.shelfInset))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(destination, display: true)
        } completionHandler: { [weak self] in
            // NSAnimationContext runs its completion on the main thread; the closure's
            // `@Sendable` type just can't see that statically.
            MainActor.assumeIsolated {
                guard let self, self.closeToken == token else { return }
                self.finishHide(panel, restoreFocus: restoreFocus)
            }
        }
    }

    /// Orders the panel out after it has cleared the screen. `onDidHide`
    /// (which clears the shelf's transient selection/preview state) fires here, at the end
    /// of the close animation, so that content doesn't visibly reset while the panel is
    /// still sliding out.
    private func finishHide(_ panel: KeyablePanel, restoreFocus: Bool) {
        panel.orderOut(nil)
        isHiding = false
        onDidHide?()
        if restoreFocus {
            previousApp?.activate()
        }
        let completions = pendingHideCompletions
        pendingHideCompletions.removeAll()
        completions.forEach { $0() }
    }

    // MARK: - Private

    private func makePanel() -> KeyablePanel {
        let panel = KeyablePanel(contentRect: .zero,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = theme.appearance
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isFloatingPanel = true
        // AppKit shadows a borderless window by its rectangular frame, not by the
        // SwiftUI glass shape inside it. Once the shelf floats away from the screen edge,
        // that leaves faint square corners around the rounded glass surface. Liquid Glass
        // supplies its own edge treatment, so keep the outer window itself shadowless.
        panel.hasShadow = false
        panel.delegate = self
        panel.contentView = makeContent()
        panel.sharingType = hideDuringScreenSharing ? .none : .readOnly
        panel.childWindowSharingType = hideDuringScreenSharing ? .none : .readOnly
        return panel
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .pressure]) { [weak self] event in
            guard let self, self.isVisible else { return event }
            switch event.type {
            case .keyDown:
                return (self.onKeyEvent?(event) ?? false) ? nil : event
            case .flagsChanged:
                self.onFlagsChanged?(event)
                return event
            case .pressure:
                // Fire once as the press crosses into the force-click stage (2), not on
                // every pressure sample while it's held.
                if event.stage >= 2, self.lastPressureStage < 2 {
                    self.onForceClick?()
                }
                self.lastPressureStage = event.stage
                return event
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if NSApp.modalWindow != nil { return }
        if let key = NSApp.keyWindow, let panel,
           panel.childWindows?.contains(key) == true || panel.attachedSheet === key {
            return
        }
        hide(restoreFocus: false)
    }

    /// SwiftUI's `.sheet()` (Edit/Create/Rename/Adjust Color/Tips) presents via AppKit's
    /// sheet mechanism rather than `addChildWindow`, so `KeyablePanel.childWindowSharingType`
    /// doesn't catch it — this documented `NSWindowDelegate` hook fires as the sheet is
    /// attached to `window` (the panel), before it's positioned/shown, giving a
    /// deterministic point to apply the same policy AND to reposition the sheet.
    ///
    /// The shelf panel sits at the screen bottom, so a sheet dropped from its top edge
    /// (the default) overflows off the bottom of the screen for anything tall. Raise the
    /// sheet's top so the whole sheet sits *above* the panel instead, clamped to stay on
    /// screen. The returned rect's top, in window coordinates, is where the sheet's top
    /// edge is placed; the sheet then extends downward by its own height.
    func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect) -> NSRect {
        sheet.sharingType = hideDuringScreenSharing ? .none : .readOnly
        return rect
    }

    /// Shows the modal content (edit/create/color/tips) as a full-screen child window
    /// centered on the shelf's screen, so it's fully visible above the shelf instead of
    /// overflowing off the bottom as an attached sheet does. A *child* window (not a
    /// separate panel) keeps `windowDidResignKey` from hiding the shelf underneath.
    func presentModal(_ view: NSView) {
        let host = modalPanel ?? makeModalPanel()
        host.contentView = view
        if let screen = panel?.screen ?? NSScreen.main {
            host.setFrame(screen.frame, display: true)
        }
        if let panel, host.parent !== panel {
            panel.addChildWindow(host, ordered: .above)
        }
        host.makeKeyAndOrderFront(nil)
    }

    func dismissModal() {
        guard let host = modalPanel else { return }
        panel?.removeChildWindow(host)
        host.orderOut(nil)
        panel?.makeKey()
    }

    private func makeModalPanel() -> KeyablePanel {
        let host = KeyablePanel(contentRect: .zero,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        host.level = .statusBar
        host.isOpaque = false
        host.backgroundColor = .clear
        host.hasShadow = false
        host.appearance = theme.appearance
        host.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        host.hidesOnDeactivate = false
        host.sharingType = hideDuringScreenSharing ? .none : .readOnly
        modalPanel = host
        return host
    }
}
