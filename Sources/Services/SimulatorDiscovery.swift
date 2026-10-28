import Foundation
import Combine

@MainActor
public final class SimulatorDiscovery: ObservableObject {
    public static let shared = SimulatorDiscovery()

    @Published public private(set) var bootedDevices: [SimulatorDevice] = []
    @Published public var selectedDevice: SimulatorDevice?
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var lastErrorMessage: String?

    private var timer: Timer?

    public init() {
        refresh()
        // Periodically refresh list of booted devices
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
                let (output, _, exitCode) = try await SimulatorService.shared.runXcrun(arguments: ["simctl", "list", "devices", "booted", "-j"])
                if exitCode == 0, let data = output.data(using: .utf8) {
                    let decoded = try JSONDecoder().decode(SimctlDeviceListResponse.self, from: data)
                    var found: [SimulatorDevice] = []
                    for (runtimeKey, devices) in decoded.devices {
                        let cleanRuntime = runtimeKey
                            .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                            .replacingOccurrences(of: "-", with: " ")
                        for var device in devices where device.isBooted {
                            device.runtime = cleanRuntime
                            device.rawRuntime = runtimeKey
                            found.append(device)
                        }
                    }
                    self.bootedDevices = found
                    if let current = self.selectedDevice, found.contains(where: { $0.udid == current.udid }) {
                        // Keep current selection
                    } else {
                        self.selectedDevice = found.first
                    }
                    self.lastErrorMessage = nil
                } else {
                    self.bootedDevices = []
                    self.selectedDevice = nil
                }
            } catch {
                self.lastErrorMessage = error.localizedDescription
            }
            self.isScanning = false
        }
    }

    /// Formats the display name. If multiple booted devices share the same name, appends short version (e.g. "iPhone 17 (v26)").
    public func displayName(for device: SimulatorDevice) -> String {
        let duplicates = bootedDevices.filter { $0.name == device.name }
        if duplicates.count > 1, let ver = device.shortVersion, !ver.isEmpty {
            return "\(device.name) (\(ver))"
        }
        return device.name
    }

    public var selectedDeviceDisplayName: String {
        guard let dev = selectedDevice else { return "No Sim Booted" }
        return displayName(for: dev)
    }

    public var targetDeviceIdentifier: String {
        return selectedDevice?.udid ?? "booted"
    }
}
