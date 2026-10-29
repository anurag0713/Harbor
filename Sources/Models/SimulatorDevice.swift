import Foundation

public struct SimulatorDevice: Identifiable, Codable, Hashable, Sendable {
    public let udid: String
    public let name: String
    public let state: String
    public let isAvailable: Bool?
    public var runtime: String?
    public var rawRuntime: String?
    public var dataPath: String?

    public var id: String { udid }

    public var isBooted: Bool {
        return state.lowercased() == "booted"
    }

    public var label: String {
        if let runtime = runtime, !runtime.isEmpty {
            return "\(name) · \(runtime)"
        }
        return name
    }

    public var shortVersion: String? {
        guard let source = rawRuntime ?? runtime else { return nil }
        let clean = source
            .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
            .replacingOccurrences(of: " ", with: "-")
        let components = clean.components(separatedBy: "-")
        guard components.count > 1 else { return nil }
        let versionParts = components.dropFirst().joined(separator: ".")
        if versionParts.hasSuffix(".0") {
            return "v" + String(versionParts.dropLast(2))
        }
        return "v" + versionParts
    }

    public init(
        udid: String,
        name: String,
        state: String,
        isAvailable: Bool? = true,
        runtime: String? = nil,
        rawRuntime: String? = nil,
        dataPath: String? = nil
    ) {
        self.udid = udid
        self.name = name
        self.state = state
        self.isAvailable = isAvailable
        self.runtime = runtime
        self.rawRuntime = rawRuntime
        self.dataPath = dataPath
    }
}

public struct SimulatorRuntimeGroup: Identifiable, Hashable, Sendable {
    public let runtime: String
    public let devices: [SimulatorDevice]

    public var id: String { runtime }

    public init(runtime: String, devices: [SimulatorDevice]) {
        self.runtime = runtime
        self.devices = devices
    }
}

public struct SimctlDeviceListResponse: Codable {
    public let devices: [String: [SimulatorDevice]]
}
