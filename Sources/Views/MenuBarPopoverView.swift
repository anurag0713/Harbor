import SwiftUI

public struct MenuBarPopoverView: View {
    @ObservedObject var discovery = SimulatorDiscovery.shared
    @ObservedObject var widgetController = FloatingWidgetController.shared

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
                if discovery.allDevices.isEmpty {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 7, height: 7)
                        Text(discovery.isScanning ? "Scanning..." : "No Simulators")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(discovery.selectedDevice?.isBooted == true ? Color.green : Color.secondary.opacity(0.6))
                            .frame(width: 7, height: 7)

                        Picker("", selection: $discovery.selectedDevice) {
                            if !discovery.bootedDevices.isEmpty {
                                Section("Running") {
                                    ForEach(discovery.bootedDevices) { dev in
                                        Text(discovery.displayName(for: dev)).tag(Optional(dev))
                                    }
                                }
                            }

                            ForEach(discovery.shutdownGroups) { group in
                                Section(group.runtime) {
                                    ForEach(group.devices) { dev in
                                        Text(dev.name).tag(Optional(dev))
                                    }
                                }
                            }
                        }
                        .labelsHidden()
                        .controlSize(.mini)
                        .frame(maxWidth: 165)
                    }
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

            // Open Drop Window Button
            Button(action: {
                widgetController.toggle()
            }) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(systemName: widgetController.isVisible ? "pip.exit" : "pip.enter")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(widgetController.isVisible ? "Close Floating Drop Window" : "Open Floating Drop Window")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("Always-on-top draggable window for file imports")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: widgetController.isVisible ? "checkmark.circle.fill" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(widgetController.isVisible ? .green : .secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(widgetController.isVisible ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Divider()

            // Feature 2: Clipboard Sync
            ClipboardSyncView()

            Divider()

            // Footer / Settings
            HStack {
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
