import Foundation
import Combine

/// Maintains the list of third-party apps installed on the currently selected simulator.
/// The list is refreshed automatically when the selected device changes, and can be
/// triggered manually. `get_app_container` is intentionally NOT called here — container
/// paths are resolved fresh at transfer time to handle reinstalls correctly.
@MainActor
public final class AppCatalog: ObservableObject {
    public static let shared = AppCatalog()

    @Published public private(set) var apps: [InstalledApp] = []
    @Published public private(set) var isLoading: Bool = false

    private var lastFetchedDevice: String?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Auto-refresh whenever the selected simulator changes.
        SimulatorDiscovery.shared.$selectedDevice
            .compactMap { $0?.udid }
            .removeDuplicates()
            .sink { [weak self] udid in
                self?.fetch(for: udid)
            }
            .store(in: &cancellables)
    }

    /// Fetches if the device has changed since last fetch; no-op otherwise.
    public func fetchIfNeeded(for deviceUDID: String) {
        guard deviceUDID != lastFetchedDevice else { return }
        fetch(for: deviceUDID)
    }

    /// Forces a refresh for the current selected device.
    public func refresh() {
        guard let udid = SimulatorDiscovery.shared.selectedDevice?.udid else { return }
        lastFetchedDevice = nil     // invalidate cache
        fetch(for: udid)
    }

    // MARK: - Private

    private func fetch(for deviceUDID: String) {
        lastFetchedDevice = deviceUDID
        isLoading = true
        Task {
            let fetched = await loadApps(device: deviceUDID)
            self.apps = fetched
            self.isLoading = false
        }
    }

    private func loadApps(device: String) async -> [InstalledApp] {
        do {
            let result = try await SimulatorService.shared.runXcrun(
                arguments: ["simctl", "listapps", device]
            )
            guard result.exitCode == 0, !result.output.isEmpty else { return [] }
            return parseApps(from: result.output)
        } catch {
            return []
        }
    }

    /// Parses the XML plist output of `simctl listapps`.
    private func parseApps(from plistString: String) -> [InstalledApp] {
        guard let data = plistString.data(using: .utf8),
              let raw = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = raw as? [String: [String: Any]] else {
            return []
        }

        var result: [InstalledApp] = []
        for (bundleId, info) in dict {
            // Exclude all first-party Apple system apps.
            guard !bundleId.hasPrefix("com.apple.") else { continue }

            let displayName = (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String)
                ?? bundleId

            result.append(InstalledApp(bundleId: bundleId, displayName: displayName))
        }

        return result.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}
