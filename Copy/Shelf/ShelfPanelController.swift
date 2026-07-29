import AppKit

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class ShelfPanelController: NSObject, NSWindowDelegate {
    static let shelfHeight: CGFloat = 340

    var onKeyEvent: ((NSEvent) -> Bool)?
    var onDidHide: (() -> Void)?

    private let makeContent: () -> NSView
    private var panel: KeyablePanel?
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?

    init(makeContent: @escaping () -> NSView) {
        self.makeContent = makeContent
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
                           height: Self.shelfHeight)
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
        if let key = NSApp.keyWindow, let panel, panel.childWindows?.contains(key) == true {
            return
        }
        hide(restoreFocus: false)
    }
}
