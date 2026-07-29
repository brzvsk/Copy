import AppKit

@MainActor
enum HUD {
    private static var window: NSPanel?

    static func show(
        _ message: String,
        on screen: NSScreen? = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? .main,
        duration: TimeInterval = 1.4
    ) {
        window?.orderOut(nil)

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.sizeToFit()

        let hPad: CGFloat = 18
        let vPad: CGFloat = 10
        let size = NSSize(width: label.frame.width + hPad * 2,
                          height: label.frame.height + vPad * 2)

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true

        // M7: deliberately NOT adopting `NSGlassEffectView` (AppKit, macOS 26+) here.
        // This pill is a pure AppKit `NSPanel` outside the SwiftUI helper's reach, so
        // adopting glass would mean a second, hand-rolled macOS-26-gated code path
        // (own Reduce Transparency check, own `NSGlassEffectView.contentView`/
        // `cornerRadius` wiring) for a toast that's on screen for `duration` (1.4s
        // default) and already reads fine as a `.hudWindow` capsule. Restraint over
        // coverage: the fallback material stays the only path, on every macOS version.
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = size.height / 2
        effect.layer?.masksToBounds = true
        label.setFrameOrigin(NSPoint(x: hPad, y: vPad))
        effect.addSubview(label)
        panel.contentView = effect

        if let screen {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - size.width / 2,
                                         y: screen.visibleFrame.minY + 120))
        }
        panel.orderFrontRegardless()
        window = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                if window === panel { window = nil }
            })
        }
    }
}
