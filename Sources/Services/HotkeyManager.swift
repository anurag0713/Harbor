import AppKit
import Foundation

public final class HotkeyManager {
    public static let shared = HotkeyManager()

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private init() {}

    /// Starts monitoring for Option + Shift + V to quickly push clipboard to simulator
    public func startMonitoring(onTrigger: @escaping () -> Void) {
        stopMonitoring()

        // Local monitor (when app has focus)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains([.option, .shift]) && event.keyCode == 9 { // 9 is 'v'
                onTrigger()
                return nil
            }
            return event
        }

        // Global monitor (when app is in background, requires accessibility permissions if available)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains([.option, .shift]) && event.keyCode == 9 {
                DispatchQueue.main.async {
                    onTrigger()
                }
            }
        }
    }

    public func stopMonitoring() {
        if let local = localMonitor {
            NSEvent.removeMonitor(local)
            localMonitor = nil
        }
        if let global = globalMonitor {
            NSEvent.removeMonitor(global)
            globalMonitor = nil
        }
    }
}
