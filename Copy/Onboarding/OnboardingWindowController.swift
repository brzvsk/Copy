import AppKit
import SwiftUI

/// Hosts `OnboardingView` in a standard titled window, following the same
/// NSWindowController + NSHostingController pattern as `SettingsWindowController`
/// (see that file's doc comment for why Copy manages its own windows rather than
/// SwiftUI's `Window`/`Settings` scenes in this `LSUIElement` app).
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    convenience init() {
        // The Finish action needs to hide this same window, but `self` doesn't exist
        // until `self.init(window:)` returns — so this constructs the hosting
        // controller with a placeholder closure first, then swaps in the real one
        // below. That's safe because the window is never shown in between: SwiftUI
        // hasn't created any `@State` for the placeholder view yet, so replacing
        // `rootView` loses nothing.
        let hosting = NSHostingController(rootView: Self.freshRootView(onFinish: {}))
        hosting.sizingOptions = [.intrinsicContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Copy"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 420))
        self.init(window: window)
        window.delegate = self
        hosting.rootView = Self.freshRootView(onFinish: { [weak self] in self?.hide() })
    }

    func show() {
        if window?.isVisible != true {
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hides rather than closes — `isReleasedWhenClosed = false` means the window
    /// survives either way, but `orderOut` sidesteps running the window's close
    /// animation for what's really just a one-time flow finishing. Since this doesn't
    /// go through `close()`, it does NOT trigger `windowWillClose`.
    func hide() {
        window?.orderOut(nil)
    }

    /// Closing via the titlebar mid-step (Accessibility or Clipboard access, both of
    /// which poll live grant status on a 0.5s `Timer.publish`) needs to tear down that
    /// step's subscription and reset back to step 0 for the next `show()`.
    ///
    /// This went through two wrong turns before landing here, each corrected by
    /// building a standalone AppKit+SwiftUI repro and measuring instead of reasoning
    /// about SwiftUI's diffing:
    /// - Plainly reassigning the SAME hosting controller's `rootView` to a "fresh"
    ///   `OnboardingView` (no `.id(_:)`) was measured to NOT reliably tear down the old
    ///   step's `Timer.publish` subscription: SwiftUI treats a same-concrete-type,
    ///   same-position `rootView` update as an in-place update of the existing view
    ///   identity rather than a fresh mount, and a repro showed the old generation's
    ///   timer could keep firing after a real `windowWillClose`. The same in-place
    ///   update also left `@State` untouched — a repro `@State` counter held its old
    ///   value across the reassignment instead of reinitializing — so the flow would
    ///   silently resume wherever the user left it.
    /// - Replacing `window.contentViewController` with a brand-new
    ///   `NSHostingController` (to force a real new identity) is worse, not better: a
    ///   repro proved the OLD hosting controller is never released even after nothing
    ///   in this class references it anymore and `window.contentViewController` points
    ///   elsewhere — something in AppKit still holds it — so its old subscription
    ///   leaks forever, and every subsequent close leaks one more orphaned controller.
    /// - The fix that actually measured clean on both counts: keep reassigning
    ///   `rootView` on the SAME, still-installed hosting controller (avoiding the
    ///   orphaned-controller leak), but wrap the fresh view in `.id(UUID())` to force
    ///   SwiftUI to treat it as a genuinely new identity. A repro confirmed this both
    ///   tears down the old step's timer (stopped firing, no leak) AND resets `@State`
    ///   (the next generation's first render showed step 0, not the step it was closed
    ///   on).
    func windowWillClose(_ notification: Notification) {
        guard let hosting = window?.contentViewController as? NSHostingController<AnyView> else { return }
        hosting.rootView = Self.freshRootView(onFinish: { [weak self] in self?.hide() })
    }

    /// Type-erased to `AnyView` because `.id(_:)` changes the concrete return type —
    /// this needs to stay assignable to the same `NSHostingController<AnyView>.rootView`
    /// both at construction and every subsequent `windowWillClose` reset.
    private static func freshRootView(onFinish: @escaping () -> Void) -> AnyView {
        AnyView(OnboardingView(onFinish: onFinish).id(UUID()))
    }
}
