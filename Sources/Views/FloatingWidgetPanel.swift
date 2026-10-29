import AppKit
import SwiftUI

@MainActor
public final class FloatingWidgetController: ObservableObject {
    public static let shared = FloatingWidgetController()

    @Published public var isVisible: Bool = false
    @Published public var isCollapsed: Bool = UserDefaults.standard.bool(forKey: "HarborFloatingWidgetCollapsed") {
        didSet {
            UserDefaults.standard.set(isCollapsed, forKey: "HarborFloatingWidgetCollapsed")
            FloatingWidgetPanel.shared.setCollapsed(isCollapsed, animated: true)
        }
    }

    private init() {
        // Break circular dependency during static initialization
        self.isVisible = false
    }

    public func show() {
        FloatingWidgetPanel.shared.makeKeyAndOrderFront(nil)
        isVisible = true
    }

    public func hide() {
        FloatingWidgetPanel.shared.orderOut(nil)
        isVisible = false
    }

    public func toggle() {
        if FloatingWidgetPanel.shared.isVisible {
            hide()
        } else {
            show()
        }
    }

    public func toggleCollapsed() {
        isCollapsed.toggle()
    }
}

@MainActor
public final class FloatingWidgetPanel: NSPanel {
    public static let shared = FloatingWidgetPanel()

    public static let panelWidth: CGFloat = 320
    public static let expandedHeight: CGFloat = 380
    public static let collapsedHeight: CGFloat = 44

    private init() {
        let isCollapsed = UserDefaults.standard.bool(forKey: "HarborFloatingWidgetCollapsed")
        let height = isCollapsed ? Self.collapsedHeight : Self.expandedHeight

        super.init(
            contentRect: NSRect(x: 100, y: 100, width: Self.panelWidth, height: height),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Restore saved position if available
        if let savedOrigin = UserDefaults.standard.string(forKey: "HarborFloatingWidgetOrigin") {
            let point = NSPointFromString(savedOrigin)
            self.setFrameOrigin(point)
        } else if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - Self.panelWidth - 24
            let y = screen.visibleFrame.maxY - height - 48
            self.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.contentView = NSHostingView(rootView: FloatingWidgetView())
    }

    public func savePosition() {
        let originStr = NSStringFromPoint(self.frame.origin)
        UserDefaults.standard.set(originStr, forKey: "HarborFloatingWidgetOrigin")
    }

    public func setCollapsed(_ collapsed: Bool, animated: Bool) {
        let currentFrame = self.frame
        let targetHeight = collapsed ? Self.collapsedHeight : Self.expandedHeight
        let newY = currentFrame.maxY - targetHeight
        let newFrame = NSRect(x: currentFrame.minX, y: newY, width: Self.panelWidth, height: targetHeight)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(newFrame, display: true)
            } completionHandler: {
                self.savePosition()
            }
        } else {
            self.setFrame(newFrame, display: true)
            self.savePosition()
        }
    }

    public func toggleVisibility() {
        if isVisible {
            orderOut(nil)
            FloatingWidgetController.shared.isVisible = false
        } else {
            makeKeyAndOrderFront(nil)
            FloatingWidgetController.shared.isVisible = true
        }
    }
}
