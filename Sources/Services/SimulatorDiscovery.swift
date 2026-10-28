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
                    for (runtime, devices) in decoded.devices {
                        let cleanRuntime = runtime
                            .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                            .replacingOccurrences(of: "-", with: " ")
                        for var device in devices where device.isBooted {
                            device.runtime = cleanRuntime
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

    public var targetDeviceIdentifier: String {
        return selectedDevice?.udid ?? "booted"
    }
}
