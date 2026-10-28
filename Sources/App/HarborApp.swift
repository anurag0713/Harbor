import SwiftUI

@main
struct HarborApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Harbor", systemImage: "ferry.fill") {
            MenuBarPopoverView()
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start global hotkey monitoring (Option + Shift + V)
        HotkeyManager.shared.startMonitoring {
            Task { @MainActor in
                _ = await ClipboardService.shared.pushToSimulator(
                    targetDevice: SimulatorDiscovery.shared.targetDeviceIdentifier
                )
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.stopMonitoring()
    }
}
