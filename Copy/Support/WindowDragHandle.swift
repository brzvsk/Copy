import AppKit
import SwiftUI

/// A transparent region that drags its window when pressed, placed behind the paste-stack
/// header. The palette is a non-activating panel, so `isMovableByWindowBackground` is off;
/// this drives the drag explicitly via `performDrag`, and accepts the first mouse so it
/// works while Copy is inactive.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
