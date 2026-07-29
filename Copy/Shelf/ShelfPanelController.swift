import AppKit

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// SwiftUI's `.popover()` presents its content in a separate `NSWindow` attached to
    /// this one via `addChildWindow` — a different window than the panel itself, so
    /// merely setting the panel's own `sharingType` doesn't exclude it from capture.
    /// Whoever owns this panel (`ShelfPanelController`/`PasteStackController`) keeps this
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
    static let shelfHeight: CGFloat = 340
    /// Panel height while `SettingsStore.compactShelf` is on, sized to `Tokens.compactCardHeight`
    /// plus the same header/divider/padding chrome `shelfHeight` allows for above the
    /// (shorter) card row. `ShelfHeader` isn't shortened in compact mode, so the fixed
    /// chrome above the card row (header + divider + `ShelfItemsRow`'s own vertical
    /// padding) is ~229pt; 232 left only ~3pt of margin before cards could clip against
    /// the panel's bottom edge, so this carries the same ~7% margin `shelfHeight` gives
    /// the standard card row.
    static let compactShelfHeight: CGFloat = 244

    var onKeyEvent: ((NSEvent) -> Bool)?
    var onDidHide: (() -> Void)?

    private let makeContent: () -> NSView
    private var panel: KeyablePanel?
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?
    private var hideDuringScreenSharing: Bool
    private var compactShelf: Bool

    init(hideDuringScreenSharing: Bool, compactShelf: Bool, makeContent: @escaping () -> NSView) {
        self.hideDuringScreenSharing = hideDuringScreenSharing
        self.compactShelf = compactShelf
        self.makeContent = makeContent
    }

    private var currentShelfHeight: CGFloat {
        compactShelf ? Self.compactShelfHeight : Self.shelfHeight
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
        let frame = NSRect(x: screen.visibleFrame.minX,
                           y: screen.visibleFrame.minY,
                           width: screen.visibleFrame.width,
                           height: currentShelfHeight)
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

        let frame = NSRect(x: screen.visibleFrame.minX,
                           y: screen.visibleFrame.minY,
                           width: screen.visibleFrame.width,
                           height: currentShelfHeight)
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(reduceMotion ? frame : frame.offsetBy(dx: 0, dy: -24), display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
        installKeyMonitor()
    }

    func hide(restoreFocus: Bool) {
        guard isVisible else { return }
        removeKeyMonitor()
        panel?.orderOut(nil)
        if restoreFocus {
            previousApp?.activate()
        }
        onDidHide?()
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
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isFloatingPanel = true
        panel.delegate = self
        panel.contentView = makeContent()
        panel.sharingType = hideDuringScreenSharing ? .none : .readOnly
        panel.childWindowSharingType = hideDuringScreenSharing ? .none : .readOnly
        return panel
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            return (self.onKeyEvent?(event) ?? false) ? nil : event
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

    /// SwiftUI's `.sheet()` (Edit/Create/Rename/Adjust Color) presents via AppKit's
    /// sheet mechanism rather than `addChildWindow`, so `KeyablePanel.childWindowSharingType`
    /// doesn't catch it — this documented `NSWindowDelegate` hook fires as the sheet is
    /// attached to `window` (the panel), before it's positioned/shown, giving a
    /// deterministic point to apply the same policy.
    func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect) -> NSRect {
        sheet.sharingType = hideDuringScreenSharing ? .none : .readOnly
        return rect
    }
}
