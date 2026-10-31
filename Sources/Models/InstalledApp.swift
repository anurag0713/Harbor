import Foundation

public struct InstalledApp: Identifiable, Sendable, Hashable {
    public let bundleId: String
    public let displayName: String

    public var id: String { bundleId }

    public init(bundleId: String, displayName: String) {
        self.bundleId = bundleId
        self.displayName = displayName
    }
}
