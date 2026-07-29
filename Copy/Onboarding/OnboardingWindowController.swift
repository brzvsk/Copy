import AppKit
import SwiftUI

/// Hosts `OnboardingView` in a standard titled window, following the same
/// NSWindowController + NSHostingController pattern as `SettingsWindowController`
/// (see that file's doc comment for why Copy manages its own windows rather than
/// SwiftUI's `Window`/`Settings` scenes in this `LSUIElement` app).
@MainActor
final class OnboardingWindowController: NSWindowController {
    convenience init() {
        // The Finish action needs to hide this same window, but `self` doesn't exist
        // until `self.init(window:)` returns — so this constructs the hosting
        // controller with a placeholder closure first, then swaps in the real one
        // below. That's safe because the window is never shown in between: SwiftUI
        // hasn't created any `@State` for the placeholder `OnboardingView` yet, so
        // replacing `rootView` loses nothing.
        let hosting = NSHostingController(rootView: OnboardingView(onFinish: {}))
        // Same first-launch sizing floor as `SettingsWindowController` — SwiftUI hasn't
        // run a layout pass yet when this window is constructed.
        hosting.sizingOptions = [.intrinsicContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Copy"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 420))
        self.init(window: window)
        hosting.rootView = OnboardingView(onFinish: { [weak self] in self?.hide() })
    }

    func show() {
        if window?.isVisible != true {
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hides rather than closes — `isReleasedWhenClosed = false` means the window (and
    /// its hosted `OnboardingView` state) survives either way, but `orderOut` sidesteps
    /// running the window's close animation for what's really just a one-time flow
    /// finishing.
    func hide() {
        window?.orderOut(nil)
    }
}
