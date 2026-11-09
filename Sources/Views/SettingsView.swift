import SwiftUI
import AppKit
import ServiceManagement

public struct SettingsView: View {
    @AppStorage("HarborAutoExpandOnDrop") private var autoExpandOnDrop: Bool = true
    @AppStorage("HarborAutoClearOnSuccess") private var autoClearOnSuccess: Bool = true
    @State private var launchAtLogin: Bool = false

    public init() {}

    public var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            hotkeysTab
                .tabItem {
                    Label("Hotkeys", systemImage: "keyboard")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 440, height: 260)
        .padding(16)
        .onAppear {
            checkLaunchAtLoginStatus()
        }
    }

    // MARK: - General Tab
    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        launchAtLogin = newValue
                        setLaunchAtLogin(enabled: newValue)
                    }
                ))

                Toggle("Auto-expand Drop Window when items are dropped", isOn: $autoExpandOnDrop)

                Toggle("Auto-dismiss success message after sending", isOn: $autoClearOnSuccess)
            } footer: {
                Text("Harbor runs quietly in your menu bar and stays ready for fast simulator interactions.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Hotkeys Tab
    private var hotkeysTab: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync Mac Clipboard → Simulator")
                            .font(.system(size: 12, weight: .medium))
                        Text("Pushes host pasteboard contents directly into the target device.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text("⌥ ⇧ V")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(6)
                }
            } footer: {
                Text("Global hotkeys are active system-wide across all applications.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About Tab
    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .cornerRadius(12)

            VStack(spacing: 3) {
                Text("Harbor")
                    .font(.system(size: 15, weight: .bold))

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
                    Text("Version \(version) (\(build))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Text("A companion for Xcode Device Hub & iOS Simulators")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }

            HStack(spacing: 12) {
                Button(action: {
                    if let url = URL(string: "https://github.com/anurag0713/Harbor") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Label("GitHub Repository", systemImage: "link")
                        .font(.system(size: 11))
                }

                Button(action: {
                    if let url = URL(string: "https://github.com/anurag0713/Harbor/releases") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Label("Releases", systemImage: "arrow.down.circle")
                        .font(.system(size: 11))
                }
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helper Methods
    private func checkLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update launch at login status: \(error)")
            }
        }
    }
}

@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowController()

    private var window: NSWindow?

    public func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 290),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Harbor Settings"
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.contentView = NSHostingView(rootView: SettingsView())

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
