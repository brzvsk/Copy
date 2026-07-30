import AppKit
import SwiftUI

/// Captures mouse events over its region so clicks don't fall through the panel to the
/// app behind, and accepts the first mouse so they register even while Copy is inactive
/// (the paste-stack palette is a non-activating, never-key panel). On macOS 26 the glass
/// material is a pure visual effect with no backing NSView, so without a capture layer the
/// panel's empty areas are click-through. A `movesWindow` region drags the window on
/// mouse-down (via `performDrag`, since the panel's `isMovableByWindowBackground` is off so
/// list rows stay reorder-draggable); a fixed region just absorbs the click.
private final class MouseRegionView: NSView {
    var movesWindow = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if movesWindow {
            window?.performDrag(with: event)
        }
        // Fixed region: absorb the event (do nothing) so it doesn't pass through.
    }
}

/// The panel's `contentView`, wrapping the SwiftUI hosting view. Because it sits at the
/// top of the panel's view hierarchy, its default hit-testing returns *itself* for any
/// point the hosting view leaves unhandled (the empty glass areas on macOS 26), which
/// stops clicks from falling through the panel to the app behind — and accepting the
/// first mouse makes those clicks register while Copy is inactive.
final class ClickCapturingContainer: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { /* absorb */ }
}

/// A window-draggable region, used behind the palette header.
struct WindowMoveArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = MouseRegionView(); view.movesWindow = true; return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// A non-draggable capture region (the palette body): absorbs clicks so they don't fall
/// through the panel, without moving the window or stealing SwiftUI's own gestures.
struct WindowFixedArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = MouseRegionView(); view.movesWindow = false; return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
