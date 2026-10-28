import Foundation

public final class DefaultsService {
    public static let shared = DefaultsService()

    private let domain = "com.apple.dt.DeviceKit"
    private let key = "hostKeybindingPolicy"

    private init() {}

    /// Checks if the hostKeybindingPolicy is set to 0 (host shortcuts restored)
    public func isHostKeybindingFixActive() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", domain, key]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    return str == "0"
                }
            }
        } catch {
            return false
        }
        return false
    }

    /// Sets hostKeybindingPolicy to 0 (enable fix) or 1 (default Xcode behavior)
    @discardableResult
    public func setHostKeybindingFix(enabled: Bool) -> TransferResult {
        let value = enabled ? "0" : "1"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", domain, key, "-int", value]

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let statusMsg = enabled
                    ? "Applied shortcut fix. macOS shortcuts are now preserved."
                    : "Reverted to Device Hub default shortcuts."
                return .success(statusMsg)
            } else {
                return .failure("Failed to write defaults (code \(process.terminationStatus))")
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
