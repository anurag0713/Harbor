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
                        .foregroundColor(.white)
                        .font(.system(size: 15))
                    Text("Harbor")
                        .font(.system(size: 14, weight: .bold))
                }

                Spacer()

                // Simulator status & target selector
                HStack(spacing: 6) {
                    Menu {
                        if discovery.allDevices.isEmpty {
                            Text(discovery.isScanning ? "Scanning for Simulators..." : "No Simulators Found")
                        } else {
                            Picker("Target Simulator", selection: $discovery.selectedDevice) {
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
                            .pickerStyle(.inline)
                        }

                        Divider()

                        Button(action: { discovery.refresh() }) {
                            Label("Refresh Simulators", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(discovery.selectedDevice?.isBooted == true ? Color.green : (discovery.allDevices.isEmpty ? Color.orange : Color.secondary.opacity(0.6)))
                                .frame(width: 6, height: 6)

                            Text(discovery.selectedDevice != nil ? discovery.displayName(for: discovery.selectedDevice!) : (discovery.isScanning ? "Scanning..." : "No Simulators"))
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 125)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Button(action: { discovery.refresh() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(discovery.isScanning ? 360 : 0))
                            .animation(
                                discovery.isScanning
                                    ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                    : .default,
                                value: discovery.isScanning
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Refresh Simulators")
                }
            }
            .padding(.bottom, 2)

            Divider()

            // Drop Window Toggle Card
            Button(action: {
                widgetController.toggle()
            }) {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(widgetController.isVisible ? Color.accentColor : Color.primary.opacity(0.08))
                            .frame(width: 28, height: 28)
                        Image(systemName: widgetController.isVisible ? "pip.exit" : "pip.enter")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(widgetController.isVisible ? .white : .primary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Floating Drop Window")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("Always-on-top drop zone for simulators")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(widgetController.isVisible ? "Active" : "Hidden")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(widgetController.isVisible ? .green : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(widgetController.isVisible ? Color.green.opacity(0.15) : Color.primary.opacity(0.06))
                        )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(widgetController.isVisible ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(widgetController.isVisible ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
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
        .frame(width: 320)
    }
}
