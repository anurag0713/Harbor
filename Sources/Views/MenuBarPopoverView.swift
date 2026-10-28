import SwiftUI

public struct MenuBarPopoverView: View {
    @ObservedObject var discovery = SimulatorDiscovery.shared
    @State private var isFloatingWidgetVisible: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "ferry.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 15))
                    Text("Harbor")
                        .font(.system(size: 14, weight: .bold))
                }

                Spacer()

                // Simulator picker / status
                if discovery.bootedDevices.isEmpty {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 7, height: 7)
                        Text("No Sim Booted")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else if discovery.bootedDevices.count == 1, let dev = discovery.bootedDevices.first {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Text(discovery.displayName(for: dev))
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                } else {
                    Picker("", selection: $discovery.selectedDevice) {
                        ForEach(discovery.bootedDevices) { dev in
                            Text(discovery.displayName(for: dev)).tag(Optional(dev))
                        }
                    }
                    .labelsHidden()
                    .controlSize(.mini)
                    .frame(maxWidth: 160)
                }

                Button(action: { discovery.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Refresh Booted Simulators")
            }
            .padding(.bottom, 2)

            Divider()

            // Feature 1: Drag & Drop Zone
            DropZoneView(discovery: discovery)

            Divider()

            // Feature 2: Clipboard Sync
            ClipboardSyncView()

            Divider()

            // Feature 3: Host Shortcut Fix
            ShortcutFixView()

            Divider()

            // Footer / Settings
            HStack {
                Toggle("Floating Drop Pill", isOn: $isFloatingWidgetVisible)
                    .font(.system(size: 11))
                    .onChange(of: isFloatingWidgetVisible) { visible in
                        if visible {
                            FloatingWidgetPanel.shared.makeKeyAndOrderFront(nil)
                        } else {
                            FloatingWidgetPanel.shared.orderOut(nil)
                        }
                    }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 11))
                .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
