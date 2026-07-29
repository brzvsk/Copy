import AppKit
import SwiftUI

/// Hosts `SettingsView` in a standard titled window that `AppCoordinator` owns and
/// shows directly, rather than through SwiftUI's `Settings` scene.
///
/// Hands-on testing showed the `Settings` scene doesn't work for Copy's configuration:
/// Copy has no `WindowGroup` (it's a menu-bar-only, `LSUIElement` app), and in that
/// shape `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)`
/// reports `handled == true` but never actually creates a window: `NSApp.windows`
/// only ever contained the status item's own `NSStatusBarWindow` and its transient
/// `NSPopupMenuWindow`, confirmed by instrumenting the call and watching window close
/// notifications across several delays. Managing the window ourselves (the same
/// approach `ShelfPanelController` already uses for the shelf) sidesteps that
/// reflection-based mechanism entirely and needs no activation-policy tricks: a plain
/// titled `NSWindow` shows fine for an accessory app; only the Dock icon is restricted.
@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init(settings: SettingsStore) {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings))
        // Without this, `NSWindow(contentViewController:)` doesn't resolve the hosting
        // controller's preferred content size against the actual SwiftUI content on
        // Ventura+, leaving the window at AppKit's degenerate default (a 1pt-wide,
        // effectively invisible sliver) instead of sizing to the TabView underneath.
        hosting.sizingOptions = [.intrinsicContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        // `sizingOptions` alone isn't enough on first launch: SwiftUI hasn't run a
        // layout pass yet when this window is constructed, so the hosting controller's
        // intrinsic size resolves to near-zero and the window ends up a 1pt sliver.
        // An explicit floor here guarantees a real size regardless of that timing;
        // `.intrinsicContentSize` still keeps later tab-switch height changes working.
        window.setContentSize(NSSize(width: 480, height: 360))
        self.init(window: window)
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
