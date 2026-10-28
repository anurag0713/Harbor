import Foundation

public struct SimulatorDevice: Identifiable, Codable, Hashable {
    public let udid: String
    public let name: String
    public let state: String
    public let isAvailable: Bool?
    public var runtime: String?

    public var id: String { udid }

    public var isBooted: Bool {
        return state.lowercased() == "booted"
    }

    public init(udid: String, name: String, state: String, isAvailable: Bool? = true, runtime: String? = nil) {
        self.udid = udid
        self.name = name
        self.state = state
        self.isAvailable = isAvailable
        self.runtime = runtime
    }
}

public struct SimctlDeviceListResponse: Codable {
    public let devices: [String: [SimulatorDevice]]
}
