import AppKit
import SwiftUI

/// Marks a region as window-draggable. With the panel's `isMovableByWindowBackground`
/// on, AppKit moves the window when a drag begins on a view whose `mouseDownCanMoveWindow`
/// is true. A dense SwiftUI header (glass material, labels) otherwise reports false in
/// most spots, so only stray gaps drag; placing this behind the header makes the whole
/// header a reliable drag handle. Sized as a `.background`, so it never expands the layout.
struct WindowMoveArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { MoveView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class MoveView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

/// Marks a region as NOT window-draggable, so a drag there reaches SwiftUI's own gesture
/// (e.g. the paste-stack rows' drag-to-reorder) instead of moving the window.
struct WindowFixedArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { FixedView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class FixedView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}
