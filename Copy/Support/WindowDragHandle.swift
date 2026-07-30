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

    override func hitTest(_ point: NSPoint) -> NSView? {
        // We have no subviews; capture any point in our bounds. SwiftUI content painted in
        // front (buttons, row gestures) is hit-tested by the hosting view first, so this
        // only catches the genuinely empty areas.
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
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
