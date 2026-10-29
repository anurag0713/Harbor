import Foundation

public final class SimulatorService {
    public static let shared = SimulatorService()

    private init() {}

    /// Executes `xcrun` with arguments asynchronously
    @discardableResult
    public func runXcrun(arguments: [String], inputData: Data? = nil) async throws -> (output: String, error: String, exitCode: Int32) {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
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
                        inputPipe.fileHandleForWriting.closeFile()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                } else {
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                }

                process.waitUntilExit()

                let outData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let outString = String(data: outData, encoding: .utf8) ?? ""
                let errString = String(data: errData, encoding: .utf8) ?? ""

                continuation.resume(returning: (outString, errString, process.terminationStatus))
            }
        }
    }

    /// Install an .app bundle onto the simulator via `simctl install`
    public func installApp(device: String = "booted", fileURL: URL) async -> TransferResult {
        do {
            let result = try await runXcrun(arguments: ["simctl", "install", device, fileURL.path])
            if result.exitCode == 0 {
                return .success("Installed \(fileURL.lastPathComponent)")
            } else {
                let err = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
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

        var arguments = ["simctl", "addmedia", device]
        arguments.append(contentsOf: fileURLs.map { $0.path })

        do {
            let result = try await runXcrun(arguments: arguments)
            if result.exitCode == 0 {
                let count = fileURLs.count
                let label = count == 1 ? "1 item" : "\(count) items"
                return .success("Imported \(label) into Photos")
            } else {
                let err = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(err.isEmpty ? "Failed to add media (code \(result.exitCode))" : err)
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
            let result = try await runXcrun(arguments: ["simctl", "pbcopy", device], inputData: data)
            if result.exitCode == 0 {
                return .success("Copied to Simulator pasteboard")
            } else {
                let err = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(err.isEmpty ? "Failed to push clipboard" : err)
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Pull text from simulator pasteboard to Mac via `simctl pbpaste`
    public func pullClipboard(device: String = "booted") async -> (text: String?, result: TransferResult) {
        do {
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

    /// Copy files into an installed app's Documents folder
    public func copyFilesToApp(device: String = "booted", bundleId: String, fileURLs: [URL]) async -> TransferResult {
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
