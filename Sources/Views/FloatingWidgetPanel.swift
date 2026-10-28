import AppKit
import SwiftUI

public final class FloatingWidgetPanel: NSPanel {
    public static let shared = FloatingWidgetPanel()

    private init() {
        super.init(
            contentRect: NSRect(x: 100, y: 100, width: 200, height: 80),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Restore saved position if available
        if let savedOrigin = UserDefaults.standard.string(forKey: "HarborFloatingWidgetOrigin") {
            let point = NSPointFromString(savedOrigin)
            self.setFrameOrigin(point)
        } else if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - 240
            let y = screen.visibleFrame.maxY - 140
            self.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.contentView = NSHostingView(rootView: FloatingWidgetView())
    }

    public override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        // Save window position
        let originStr = NSStringFromPoint(self.frame.origin)
        UserDefaults.standard.set(originStr, forKey: "HarborFloatingWidgetOrigin")
    }

    public func toggleVisibility() {
        if isVisible {
            orderOut(nil)
        } else {
            makeKeyAndOrderFront(nil)
        }
    }
}
