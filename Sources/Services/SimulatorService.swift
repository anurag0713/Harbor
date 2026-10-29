import Foundation

public final class SimulatorService {
    public static let shared = SimulatorService()

    private init() {}

    /// Executes `xcrun` with arguments asynchronously
    @discardableResult
    public func runXcrun(arguments: [String], inputData: Data? = nil) async throws -> (output: String, error: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        if let inputData = inputData {
            let inputPipe = Pipe()
            process.standardInput = inputPipe
            do {
                try process.run()
                inputPipe.fileHandleForWriting.write(inputData)
                try? inputPipe.fileHandleForWriting.close()
            } catch {
                throw error
            }
        } else {
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                throw error
            }
        }

        async let outData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        async let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let status: Int32 = await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
        }

        let (outBytes, errBytes) = await (outData, errData)
        let outString = String(data: outBytes, encoding: .utf8) ?? ""
        let errString = String(data: errBytes, encoding: .utf8) ?? ""

        return (outString, errString, status)
    }

    /// Fixes stuck Shift / modifier keys when switching between multiple simulators in Device Hub
    public func resetKeyboardFocus(deviceUDID: String? = nil) async -> TransferResult {
        let udid: String
        if let given = deviceUDID, !given.isEmpty, given != "booted" {
            udid = given
        } else {
            udid = await SimulatorDiscovery.shared.targetDeviceIdentifier
        }

        guard !udid.isEmpty, udid != "booted" else {
            return .failure("No simulator selected to reset keyboard")
        }

        do {
            // 1. Read locale/language from target simulator
            let localeRes = try? await runXcrun(arguments: ["simctl", "spawn", udid, "defaults", "read", "-g", "AppleLocale"])
            let rawLocale = localeRes?.output.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let locale = rawLocale.isEmpty ? "en_US" : rawLocale

            // 2. Configure AppleKeyboards with hardware mapping (hw=Automatic)
            let primaryKeyboard = "\(locale)@sw=QWERTY;hw=Automatic;ml=100"
            _ = try await runXcrun(arguments: [
                "simctl", "spawn", udid, "defaults", "write", "-g", "AppleKeyboards",
                "-array", primaryKeyboard, "emoji@sw=Emoji"
            ])

            // 3. Mark ConnectHardwareKeyboard = 1 in com.apple.iphonesimulator preferences
            let dictSnippet = "{ ConnectHardwareKeyboard = 1; }"
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            proc.arguments = ["write", "com.apple.iphonesimulator", "DevicePreferences", "-dict-add", udid, dictSnippet]
            try? proc.run()
            proc.waitUntilExit()

            // Global flags
            let proc2 = Process()
            proc2.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            proc2.arguments = ["write", "com.apple.iphonesimulator", "ConnectHardwareKeyboard", "-bool", "true"]
            try? proc2.run()
            proc2.waitUntilExit()

            let proc3 = Process()
            proc3.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            proc3.arguments = ["write", "com.apple.dt.Devices", "AlwaysSimulateHardwareKeyboard", "-bool", "true"]
            try? proc3.run()
            proc3.waitUntilExit()

            // 4. Notify simulator keyboard subsystem of preferences change
            _ = try? await runXcrun(arguments: ["simctl", "spawn", udid, "notifyutil", "-p", "com.apple.keyboard.preferences.changed"])

            // 5. Restart TextInput.kbd daemon inside simulator
            _ = try? await runXcrun(arguments: ["simctl", "spawn", udid, "/bin/sh", "-c", "launchctl kill 9 gui/$(id -u)/com.apple.TextInput.kbd 2>/dev/null || true"])

            // 6. Activate DeviceHub / Simulator host window
            let activateScript = """
            tell application "System Events"
                if exists (process "DeviceHub") then
                    tell process "DeviceHub" to set frontmost to true
                else if exists (process "Simulator") then
                    tell process "Simulator" to set frontmost to true
                end if
            end tell
            """
            var err: NSDictionary?
            NSAppleScript(source: activateScript)?.executeAndReturnError(&err)

            return .success("Hardware keyboard & Shift re-enabled")
        } catch {
            return .failure("Keyboard reset failed: \(error.localizedDescription)")
        }
    }

    /// Prepares files in an unprotected temporary staging folder to avoid TCC sandboxing issues (e.g. ~/Downloads)
    public func withStagedFiles<T>(
        _ sources: [URL],
        operation: ([URL]) async throws -> T
    ) async throws -> T {
        let fileManager = FileManager.default
        let tempFolder = fileManager.temporaryDirectory.appendingPathComponent("HarborStaging-\(UUID().uuidString)", isDirectory: true)

        try fileManager.createDirectory(at: tempFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer {
            try? fileManager.removeItem(at: tempFolder)
        }

        var stagedURLs: [URL] = []
        for source in sources {
            let dest = tempFolder.appendingPathComponent(source.lastPathComponent)
            try fileManager.copyItem(at: source.resolvingSymlinksInPath(), to: dest)
            // Remove any macOS immutable flags on the copy
            try? fileManager.setAttributes([.immutable: false], ofItemAtPath: dest.path)
            stagedURLs.append(dest)
        }

        return try await operation(stagedURLs)
    }

    /// Formats simctl output to concise, actionable errors
    public static func conciseMessage(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("Source is not authorized") {
            return "The app is not allowed to show notifications. Open it in simulator and allow permissions."
        }
        if trimmed.contains("PHPhotosErrorDomain") || trimmed.contains("code=3302") {
            return "Photos could not import this media file. Ensure it is a valid supported photo or video."
        }
        if let reasonRange = trimmed.range(of: "reason: '"),
           let end = trimmed[reasonRange.upperBound...].firstIndex(of: "'") {
            return "simctl error: \(trimmed[reasonRange.upperBound..<end])"
        }
        let lines = trimmed.split(whereSeparator: \.isNewline)
        if let detail = lines.last(where: { $0.hasPrefix("\t") }) {
            return detail.trimmingCharacters(in: .whitespaces)
        }
        return lines.prefix(2).joined(separator: ": ")
    }

    /// Boots the simulator device if not already running, waiting until booted
    public func bootIfNeeded(deviceUDID: String) async throws {
        guard deviceUDID != "booted", !deviceUDID.isEmpty else { return }
        _ = try await runXcrun(arguments: ["simctl", "bootstatus", deviceUDID, "-b"])
    }

    /// Boots and reveals the simulator in Simulator.app
    public func showSimulator(deviceUDID: String) async throws {
        try await bootIfNeeded(deviceUDID: deviceUDID)
        let openProcess = Process()
        openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openProcess.arguments = ["-a", "Simulator", "--args", "-CurrentDeviceUDID", deviceUDID]
        try openProcess.run()
    }

    /// Opens a web link or app deep link (e.g. myapp://...) on the simulator via `simctl openurl`
    public func openURL(device: String = "booted", url: URL) async -> TransferResult {
        do {
            try await bootIfNeeded(deviceUDID: device)
            let result = try await runXcrun(arguments: ["simctl", "openurl", device, url.absoluteString])
            if result.exitCode == 0 {
                return .success("Opened link in simulator")
            } else {
                let err = Self.conciseMessage(result.error)
                return .failure(err.isEmpty ? "Failed to open link" : err)
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Install an .app bundle onto the simulator via `simctl install`
    public func installApp(device: String = "booted", fileURL: URL) async -> TransferResult {
        do {
            try await bootIfNeeded(deviceUDID: device)
            let result = try await runXcrun(arguments: ["simctl", "install", device, fileURL.path])
            if result.exitCode == 0 {
                return .success("Installed \(fileURL.lastPathComponent)")
            } else {
                let err = Self.conciseMessage(result.error)
                return .failure(err.isEmpty ? "Failed to install app (code \(result.exitCode))" : err)
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Add media files (images/videos) into the simulator photo library
    public func addMedia(device: String = "booted", fileURLs: [URL]) async -> TransferResult {
        guard !fileURLs.isEmpty else {
            return .failure("No files provided")
        }

        do {
            try await bootIfNeeded(deviceUDID: device)

            return try await withStagedFiles(fileURLs) { staged in
                var arguments = ["simctl", "addmedia", device]
                arguments.append(contentsOf: staged.map { $0.path })

                let result = try await runXcrun(arguments: arguments)
                if result.exitCode == 0 {
                    let count = fileURLs.count
                    let label = count == 1 ? "1 item" : "\(count) items"
                    return .success("Imported \(label) into Photos")
                } else {
                    let err = Self.conciseMessage(result.error)
                    return .failure(err.isEmpty ? "Failed to add media (code \(result.exitCode))" : err)
                }
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Push text from Mac into the simulator pasteboard via `simctl pbcopy`
    public func pushClipboard(device: String = "booted", text: String) async -> TransferResult {
        guard let data = text.data(using: .utf8) else {
            return .failure("Invalid text encoding")
        }

        do {
            try await bootIfNeeded(deviceUDID: device)
            let result = try await runXcrun(arguments: ["simctl", "pbcopy", device], inputData: data)
            if result.exitCode == 0 {
                return .success("Copied to Simulator pasteboard")
            } else {
                let err = Self.conciseMessage(result.error)
                return .failure(err.isEmpty ? "Failed to push clipboard" : err)
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Pull text from simulator pasteboard to Mac via `simctl pbpaste`
    public func pullClipboard(device: String = "booted") async -> (text: String?, result: TransferResult) {
        do {
            try await bootIfNeeded(deviceUDID: device)
            let result = try await runXcrun(arguments: ["simctl", "pbpaste", device])
            if result.exitCode == 0 {
                return (result.output, .success("Pulled clipboard from Simulator"))
            } else {
                return (nil, .failure("Failed to read simulator pasteboard"))
            }
        } catch {
            return (nil, .failure(error.localizedDescription))
        }
    }

    /// Get app data container directory
    public func getAppContainer(device: String = "booted", bundleId: String) async -> String? {
        do {
            let result = try await runXcrun(arguments: ["simctl", "get_app_container", device, bundleId, "data"])
            if result.exitCode == 0 {
                let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                return path.isEmpty ? nil : path
            }
        } catch {
            return nil
        }
        return nil
    }

    /// Resolve the simulator's Files app ("On My iPhone") storage folder
    public func filesFolder(on deviceUDID: String) async throws -> URL {
        try await bootIfNeeded(deviceUDID: deviceUDID)

        // Try lookup via simctl get_app_container groups
        let res = try? await runXcrun(arguments: ["simctl", "get_app_container", deviceUDID, "com.apple.DocumentsApp", "groups"])
        var groupURL: URL? = nil
        if let output = res?.output, res?.exitCode == 0 {
            if let path = FilesStorage.groupPath(inGroupsOutput: output) {
                groupURL = URL(fileURLWithPath: path)
            }
        }

        // Fallback: look in SimulatorDiscovery device dataPath
        if groupURL == nil {
            let allDevices = await SimulatorDiscovery.shared.allDevices
            if let device = allDevices.first(where: { $0.udid == deviceUDID }),
               let dataPath = device.dataPath {
                groupURL = FilesStorage.findGroup(inDataPath: dataPath)
            }
        }

        // Secondary fallback: standard Simulator path ~/Library/Developer/CoreSimulator/Devices/<UDID>/data
        if groupURL == nil {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let standardDataPath = home.appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(deviceUDID)/data").path
            groupURL = FilesStorage.findGroup(inDataPath: standardDataPath)
        }

        guard let group = groupURL else {
            throw NSError(domain: "Harbor", code: 404, userInfo: [NSLocalizedDescriptionKey: "Files app storage not found on device"])
        }

        return group.appendingPathComponent(FilesStorage.folderName)
    }

    /// Import files into the simulator's Files app ("On My iPhone")
    public func copyFilesToFilesApp(device: String = "booted", fileURLs: [URL]) async -> TransferResult {
        guard !fileURLs.isEmpty else { return .failure("No files provided") }
        do {
            let targetFolder = try await filesFolder(on: device)
            var count = 0
            for fileURL in fileURLs {
                try FilesStorage.copy(fileURL, into: targetFolder)
                count += 1
            }
            let label = count == 1 ? "1 file" : "\(count) files"
            return .success("Imported \(label) into Files app")
        } catch {
            return .failure("Files import error: \(error.localizedDescription)")
        }
    }

    /// Copy files into an installed app's Documents folder
    public func copyFilesToApp(device: String = "booted", bundleId: String, fileURLs: [URL]) async -> TransferResult {
        do {
            try await bootIfNeeded(deviceUDID: device)
        } catch {
            return .failure("Could not boot device: \(error.localizedDescription)")
        }

        guard let container = await getAppContainer(device: device, bundleId: bundleId) else {
            return .failure("Could not locate container for \(bundleId)")
        }

        let documentsDir = URL(fileURLWithPath: container).appendingPathComponent("Documents")
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(at: documentsDir, withIntermediateDirectories: true)
            for fileURL in fileURLs {
                let targetURL = documentsDir.appendingPathComponent(fileURL.lastPathComponent)
                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.removeItem(at: targetURL)
                }
                try fileManager.copyItem(at: fileURL, to: targetURL)
            }
            return .success("Copied \(fileURLs.count) file(s) into \(bundleId)")
        } catch {
            return .failure("Copy error: \(error.localizedDescription)")
        }
    }
}
