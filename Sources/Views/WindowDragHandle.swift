import AppKit
import SwiftUI

/// An NSView that initiates window dragging on mouse down
public final class DragWindowView: NSView {
    public override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

public struct WindowDragHandle: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> DragWindowView {
        let view = DragWindowView()
        return view
    }

    public func updateNSView(_ nsView: DragWindowView, context: Context) {}
}
