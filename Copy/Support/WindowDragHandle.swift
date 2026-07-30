import AppKit
import SwiftUI

/// A transparent region that drags its window when pressed, used as the background of a
/// panel's header. `isMovableByWindowBackground` only lets you drag from truly empty
/// (non-interactive) spots, so a dense SwiftUI header ends up draggable only from the
/// gaps between text and controls. Placing this behind the header makes the whole header
/// a reliable drag handle, while the buttons on top still receive their own clicks.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
        // Let the region participate in hit-testing (so it receives mouseDown) even
        // though it draws nothing.
        override func hitTest(_ point: NSPoint) -> NSView? {
            super.hitTest(point) === self ? self : super.hitTest(point)
        }
    }
}
