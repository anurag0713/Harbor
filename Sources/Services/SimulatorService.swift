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

        return await withTaskCancellationHandler {
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
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
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
        guard !trimmed.isEmpty else { return "Unknown error" }

        if trimmed.contains("Source is not authorized") {
            return "The app is not allowed to show notifications. Open it in simulator and allow permissions."
        }
        if trimmed.contains("PHPhotosErrorDomain") || trimmed.contains("code=3302") {
            return "Photos could not import this media file. Ensure it is a valid supported photo or video."
        }
        if trimmed.contains("-10814") {
            return "No app installed in simulator to handle this URL scheme (error -10814)."
        }
        if let reasonRange = trimmed.range(of: "reason: '"),
           let end = trimmed[reasonRange.upperBound...].firstIndex(of: "'") {
            return "simctl error: \(trimmed[reasonRange.upperBound..<end])"
        }

        let boilerplatePatterns = [
            "An error was encountered processing the command",
            "Underlying error",
            "Please try again later",
            "IXUserPresentableErrorDomain",
            "NSOSStatusErrorDomain",
            "NSPOSIXErrorDomain",
            "code="
        ]

        let lines = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard !line.isEmpty else { return false }
                for pattern in boilerplatePatterns {
                    if line.contains(pattern) { return false }
                }
                return true
            }

        if let specificCause = lines.first(where: {
            $0.contains("missing its bundle executable") ||
            $0.contains("does not contain a binary matching") ||
            $0.contains("architecture") ||
            $0.contains("not compatible") ||
            $0.contains("failed to open") ||
            $0.contains("could not be inspected")
        }) {
            return specificCause
        }

        if let first = lines.first {
            return first
        }

        return trimmed.split(whereSeparator: \.isNewline).prefix(2).joined(separator: ": ")
    }

    /// Checks whether the target .app bundle is a macOS app bundle instead of an iOS Simulator build
    public static func isMacOSAppBundle(url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "app" else { return false }

        let fm = FileManager.default
        let contentsDir = url.appendingPathComponent("Contents")
        let contentsMacOS = contentsDir.appendingPathComponent("MacOS")
        let contentsInfo = contentsDir.appendingPathComponent("Info.plist")

        // macOS app bundles use standard bundle layout with a "Contents" directory
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: contentsMacOS.path, isDirectory: &isDir), isDir.boolValue {
            return true
        }
        if fm.fileExists(atPath: contentsInfo.path) {
            return true
        }

        // Check Info.plist CFBundleSupportedPlatforms or DTPlatformName
        let plistURL = fm.fileExists(atPath: contentsInfo.path) ? contentsInfo : url.appendingPathComponent("Info.plist")
        if let data = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            if let platforms = plist["CFBundleSupportedPlatforms"] as? [String] {
                if platforms.contains("MacOSX") && !platforms.contains("iPhoneSimulator") {
                    return true
                }
            }
            if let platformName = plist["DTPlatformName"] as? String, platformName.lowercased() == "macosx" {
                return true
            }
        }

        return false
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
                let combinedErr = "\(result.error) \(result.output)"
                if combinedErr.contains("-10814") {
                    let scheme = url.scheme ?? url.absoluteString
                    let err = ItemTransferError.unsupportedScheme(scheme: scheme)
                    return .failure(err.detailedExplanation, detail: err)
                }
                let err = Self.conciseMessage(result.error.isEmpty ? result.output : result.error)
                let detail = ItemTransferError.general(short: err.isEmpty ? "Failed to open link" : err, detailed: err)
                return .failure(err.isEmpty ? "Failed to open link" : err, detail: detail)
            }
        } catch {
            let detail = ItemTransferError.general(short: "Error opening link", detailed: error.localizedDescription)
            return .failure(error.localizedDescription, detail: detail)
        }
    }

    /// Install an .app bundle onto the simulator via `simctl install`
    public func installApp(device: String = "booted", fileURL: URL) async -> TransferResult {
        if Self.isMacOSAppBundle(url: fileURL) {
            let error = ItemTransferError.macOSApp(name: fileURL.lastPathComponent)
            return .failure(error.detailedExplanation, detail: error)
        }

        do {
            try await bootIfNeeded(deviceUDID: device)
            let result = try await runXcrun(arguments: ["simctl", "install", device, fileURL.path])
            if result.exitCode == 0 {
                return .success("Installed \(fileURL.lastPathComponent)")
            } else {
                let rawErr = result.error.isEmpty ? result.output : result.error
                let concise = Self.conciseMessage(rawErr)
                let category: ItemTransferError.Category
                let short: String
                if rawErr.contains("missing its bundle executable") {
                    category = .missingExecutable
                    short = "Missing executable"
                } else if rawErr.contains("architecture") || rawErr.contains("does not contain a binary matching") {
                    category = .incompatibleArchitecture
                    short = "Incompatible architecture"
                } else {
                    category = .general(concise)
                    short = "Install failed"
                }
                let detail = ItemTransferError(
                    shortReason: short,
                    detailedExplanation: concise.isEmpty ? "Failed to install app (code \(result.exitCode))" : concise,
                    category: category
                )
                return .failure(detail.detailedExplanation, detail: detail)
            }
        } catch {
            let detail = ItemTransferError.general(short: "Install error", detailed: error.localizedDescription)
            return .failure(error.localizedDescription, detail: detail)
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
                    let err = Self.conciseMessage(result.error.isEmpty ? result.output : result.error)
                    let msg = err.isEmpty ? "Failed to add media (code \(result.exitCode))" : err
                    let detail = ItemTransferError.photosError(reason: msg)
                    return .failure(msg, detail: detail)
                }
            }
        } catch {
            let detail = ItemTransferError.photosError(reason: error.localizedDescription)
            return .failure(error.localizedDescription, detail: detail)
        }
    }

    /// Imports media files progressively in resilient chunks.
    /// Live calls `onItemSuccess` as each item is confirmed imported.
    /// If a chunk fails, attempts files individually to isolate corrupt files.
    /// If simulator stops/shuts down, aborts subsequent chunks cleanly.
    public func addMediaProgressive(
        device: String = "booted",
        items: [QueueItem],
        onItemSuccess: (@MainActor (UUID) -> Void)? = nil
    ) async -> (succeededIDs: Set<UUID>, failedIDs: Set<UUID>, errors: [UUID: ItemTransferError]) {
        guard !items.isEmpty else { return ([], [], [:]) }

        do {
            try await bootIfNeeded(deviceUDID: device)
        } catch {
            let err = ItemTransferError.general(short: "Could not boot simulator", detailed: error.localizedDescription)
            let allFailed = Set(items.map(\.id))
            var map: [UUID: ItemTransferError] = [:]
            for id in allFailed { map[id] = err }
            return ([], allFailed, map)
        }

        var succeededIDs = Set<UUID>()
        var failedIDs = Set<UUID>()
        var errors: [UUID: ItemTransferError] = [:]

        // Chunk into batches of 8 for optimal speed while keeping recovery granular
        let chunkSize = 8
        var chunks: [[QueueItem]] = []
        for i in stride(from: 0, to: items.count, by: chunkSize) {
            chunks.append(Array(items[i..<min(i + chunkSize, items.count)]))
        }

        var simulatorDied = false

        for chunk in chunks {
            if Task.isCancelled || simulatorDied {
                let isCancelled = Task.isCancelled
                let err = isCancelled
                    ? ItemTransferError.general(short: "Stopped by user", detailed: "Transfer was stopped.")
                    : ItemTransferError.general(short: "Simulator was closed", detailed: "Simulator stopped before this item could be transferred.")
                for item in chunk {
                    failedIDs.insert(item.id)
                    errors[item.id] = err
                }
                continue
            }

            let chunkURLs = chunk.map(\.url)
            let res = await addMedia(device: device, fileURLs: chunkURLs)

            if Task.isCancelled {
                // If cancelled while addMedia was running, mark chunk as stopped
                for item in chunk {
                    if !succeededIDs.contains(item.id) {
                        failedIDs.insert(item.id)
                        errors[item.id] = ItemTransferError.general(short: "Stopped by user", detailed: "Transfer was stopped.")
                    }
                }
                continue
            }

            if res.isSuccess {
                for item in chunk {
                    succeededIDs.insert(item.id)
                    await onItemSuccess?(item.id)
                }
            } else {
                let isDead = res.message.contains("LaunchdSimError") ||
                             res.message.contains("shut down") ||
                             res.message.contains("not booted")

                if isDead {
                    simulatorDied = true
                    let err = ItemTransferError.general(short: "Simulator was closed", detailed: "Simulator shut down during import.")
                    for item in chunk {
                        failedIDs.insert(item.id)
                        errors[item.id] = err
                    }
                } else {
                    // Fall back to item-by-item for this failing chunk to isolate bad files
                    for item in chunk {
                        if Task.isCancelled {
                            failedIDs.insert(item.id)
                            errors[item.id] = ItemTransferError.general(short: "Stopped by user", detailed: "Transfer was stopped.")
                            continue
                        }
                        let singleRes = await addMedia(device: device, fileURLs: [item.url])
                        if singleRes.isSuccess {
                            succeededIDs.insert(item.id)
                            await onItemSuccess?(item.id)
                        } else {
                            failedIDs.insert(item.id)
                            let isSingleDead = singleRes.message.contains("LaunchdSimError") ||
                                               singleRes.message.contains("shut down") ||
                                               singleRes.message.contains("not booted")
                            if isSingleDead {
                                simulatorDied = true
                                let err = ItemTransferError.general(short: "Simulator was closed", detailed: "Simulator shut down during import.")
                                errors[item.id] = err
                            } else {
                                let err = singleRes.errorDetail ?? ItemTransferError.photosError(reason: singleRes.message)
                                errors[item.id] = err
                            }
                        }
                    }
                }
            }
        }

        return (succeededIDs, failedIDs, errors)
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

    /// Import files into the simulator's Files app ("On My iPhone") progressively with live progress callbacks
    public func copyFilesToFilesAppProgressive(
        device: String = "booted",
        items: [QueueItem],
        onItemSuccess: (@MainActor (UUID) -> Void)? = nil
    ) async -> (succeededIDs: Set<UUID>, failedIDs: Set<UUID>, errors: [UUID: ItemTransferError]) {
        guard !items.isEmpty else { return ([], [], [:]) }
        do {
            let targetFolder = try await filesFolder(on: device)
            var succeeded = Set<UUID>()
            var failed = Set<UUID>()
            var errors: [UUID: ItemTransferError] = [:]

            for item in items {
                if Task.isCancelled {
                    failed.insert(item.id)
                    errors[item.id] = ItemTransferError.general(short: "Stopped by user", detailed: "Transfer was stopped.")
                    continue
                }
                do {
                    try FilesStorage.copy(item.url, into: targetFolder)
                    succeeded.insert(item.id)
                    await onItemSuccess?(item.id)
                } catch {
                    failed.insert(item.id)
                    errors[item.id] = ItemTransferError.general(short: "File copy failed", detailed: error.localizedDescription)
                }
            }
            return (succeeded, failed, errors)
        } catch {
            let err = ItemTransferError.general(short: "Files app storage not found", detailed: error.localizedDescription)
            let allFailed = Set(items.map(\.id))
            var map: [UUID: ItemTransferError] = [:]
            for id in allFailed { map[id] = err }
            return ([], allFailed, map)
        }
    }

    /// Copy files into an installed app's Documents folder progressively with live progress callbacks
    public func copyFilesToAppProgressive(
        device: String = "booted",
        bundleId: String,
        items: [QueueItem],
        onItemSuccess: (@MainActor (UUID) -> Void)? = nil
    ) async -> (succeededIDs: Set<UUID>, failedIDs: Set<UUID>, errors: [UUID: ItemTransferError]) {
        guard !items.isEmpty else { return ([], [], [:]) }
        do {
            try await bootIfNeeded(deviceUDID: device)
        } catch {
            let err = ItemTransferError.general(short: "Could not boot device", detailed: error.localizedDescription)
            let allFailed = Set(items.map(\.id))
            var map: [UUID: ItemTransferError] = [:]
            for id in allFailed { map[id] = err }
            return ([], allFailed, map)
        }

        guard let container = await getAppContainer(device: device, bundleId: bundleId) else {
            let err = ItemTransferError.general(short: "App container not found", detailed: "Could not locate container for \(bundleId)")
            let allFailed = Set(items.map(\.id))
            var map: [UUID: ItemTransferError] = [:]
            for id in allFailed { map[id] = err }
            return ([], allFailed, map)
        }

        let documentsDir = URL(fileURLWithPath: container).appendingPathComponent("Documents")
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: documentsDir, withIntermediateDirectories: true)

        var succeeded = Set<UUID>()
        var failed = Set<UUID>()
        var errors: [UUID: ItemTransferError] = [:]

        for item in items {
            if Task.isCancelled {
                failed.insert(item.id)
                errors[item.id] = ItemTransferError.general(short: "Stopped by user", detailed: "Transfer was stopped.")
                continue
            }
            do {
                let targetURL = documentsDir.appendingPathComponent(item.url.lastPathComponent)
                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.removeItem(at: targetURL)
                }
                try fileManager.copyItem(at: item.url, to: targetURL)
                succeeded.insert(item.id)
                await onItemSuccess?(item.id)
            } catch {
                failed.insert(item.id)
                errors[item.id] = ItemTransferError.general(short: "Copy failed", detailed: error.localizedDescription)
            }
        }
        return (succeeded, failed, errors)
    }
}
