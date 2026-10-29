import Foundation
import Combine

@MainActor
public final class SimulatorDiscovery: ObservableObject {
    public static let shared = SimulatorDiscovery()

    @Published public private(set) var allDevices: [SimulatorDevice] = []
    @Published public private(set) var bootedDevices: [SimulatorDevice] = []
    @Published public private(set) var shutdownGroups: [SimulatorRuntimeGroup] = []
    @Published public var selectedDevice: SimulatorDevice?
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var lastErrorMessage: String?

    private var timer: Timer?

    public init() {
        refresh()
        // Periodically refresh list of available devices
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    public func refresh() {
        isScanning = true
        Task {
            do {
                let (output, _, exitCode) = try await SimulatorService.shared.runXcrun(arguments: ["simctl", "list", "devices", "available", "-j"])
                if exitCode == 0, let data = output.data(using: .utf8) {
                    let decoded = try JSONDecoder().decode(SimctlDeviceListResponse.self, from: data)

                    var all: [SimulatorDevice] = []
                    var booted: [SimulatorDevice] = []
                    var groupedByRuntime: [String: [SimulatorDevice]] = [:]

                    // Only support iOS simulators (matching SimParcel)
                    for (runtimeKey, devices) in decoded.devices {
                        let prefix = "com.apple.CoreSimulator.SimRuntime."
                        guard runtimeKey.hasPrefix(prefix) else { continue }
                        let rawSuffix = String(runtimeKey.dropFirst(prefix.count))
                        // Must be iOS
                        guard rawSuffix.hasPrefix("iOS") else { continue }

                        let cleanRuntime = rawSuffix.replacingOccurrences(of: "-", with: " ")
                            .replacingOccurrences(of: "iOS ", with: "iOS ")

                        var runtimeDevices: [SimulatorDevice] = []
                        for var device in devices {
                            device.runtime = cleanRuntime
                            device.rawRuntime = runtimeKey
                            all.append(device)
                            if device.isBooted {
                                booted.append(device)
                            } else {
                                runtimeDevices.append(device)
                            }
                        }

                        if !runtimeDevices.isEmpty {
                            groupedByRuntime[cleanRuntime] = runtimeDevices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                        }
                    }

                    // Sort runtime groups descending (newest iOS first)
                    let sortedGroups = groupedByRuntime.map { SimulatorRuntimeGroup(runtime: $0.key, devices: $0.value) }
                        .sorted { $0.runtime > $1.runtime }

                    self.allDevices = all
                    self.bootedDevices = booted
                    self.shutdownGroups = sortedGroups

                    // Preserve or pick selection
                    if let current = self.selectedDevice, let updated = all.first(where: { $0.udid == current.udid }) {
                        self.selectedDevice = updated
                    } else {
                        // Prefer first booted, else first available
                        self.selectedDevice = booted.first ?? all.first
                    }
                    self.lastErrorMessage = nil
                } else {
                    self.allDevices = []
                    self.bootedDevices = []
                    self.shutdownGroups = []
                    self.selectedDevice = nil
                }
            } catch {
                self.lastErrorMessage = error.localizedDescription
            }
            self.isScanning = false
        }
    }

    /// Formats the display name. If multiple devices share the same name, appends short version (e.g. "iPhone 16 (v18.2)").
    public func displayName(for device: SimulatorDevice) -> String {
        let duplicates = allDevices.filter { $0.name == device.name }
        if duplicates.count > 1, let ver = device.shortVersion, !ver.isEmpty {
            return "\(device.name) (\(ver))"
        }
        return device.name
    }

    public var selectedDeviceDisplayName: String {
        guard let dev = selectedDevice else { return "No Simulators Found" }
        let status = dev.isBooted ? "" : " (Offline)"
        return "\(displayName(for: dev))\(status)"
    }

    public var targetDeviceIdentifier: String {
        return selectedDevice?.udid ?? "booted"
    }
}
