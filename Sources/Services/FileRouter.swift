import Foundation

public final class FileRouter {
    public static let shared = FileRouter()

    private let mediaExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "webp",
        "mp4", "mov", "m4v", "avi", "mkv"
    ]

    private init() {}

    public enum FileCategory {
        case appBundle([URL])
        case media([URL])
        case apnsPayload(URL)
        case link([URL])
        case generalDocument([URL])
    }

    public func categorize(urls: [URL]) -> [FileCategory] {
        var apps: [URL] = []
        var media: [URL] = []
        var links: [URL] = []
        var others: [URL] = []
        var apns: [URL] = []

        for url in urls {
            if !url.isFileURL {
                links.append(url)
                continue
            }

            let ext = url.pathExtension.lowercased()
            if ext == "app" {
                apps.append(url)
            } else if ext == "apns" {
                apns.append(url)
            } else if ext == "webloc" || ext == "url" {
                if let extracted = extractURLFromShortcutFile(url: url) {
                    links.append(extracted)
                } else {
                    others.append(url)
                }
            } else if mediaExtensions.contains(ext) {
                media.append(url)
            } else {
                others.append(url)
            }
        }

        var categories: [FileCategory] = []
        if !apps.isEmpty {
            categories.append(.appBundle(apps))
        }
        if !media.isEmpty {
            categories.append(.media(media))
        }
        for apnsURL in apns {
            categories.append(.apnsPayload(apnsURL))
        }
        if !links.isEmpty {
            categories.append(.link(links))
        }
        if !others.isEmpty {
            categories.append(.generalDocument(others))
        }
        return categories
    }

    public func routeAndTransfer(urls: [URL], targetDevice: String = "booted", targetBundleId: String? = nil) async -> TransferResult {
        guard !urls.isEmpty else {
            return .failure("No files dropped")
        }

        let categories = categorize(urls: urls)
        var messages: [String] = []
        var allSucceeded = true

        for category in categories {
            switch category {
            case .appBundle(let appURLs):
                for appURL in appURLs {
                    let result = await SimulatorService.shared.installApp(device: targetDevice, fileURL: appURL)
                    messages.append(result.message)
                    if !result.isSuccess { allSucceeded = false }
                }

            case .media(let mediaURLs):
                let result = await SimulatorService.shared.addMedia(device: targetDevice, fileURLs: mediaURLs)
                messages.append(result.message)
                if !result.isSuccess { allSucceeded = false }

            case .apnsPayload(let apnsURL):
                // If .apns, attempt simctl push
                let bundleId = targetBundleId ?? (extractBundleIdFromAPNS(url: apnsURL) ?? "")
                if bundleId.isEmpty {
                    messages.append("APNs dropped but no target bundle ID found")
                    allSucceeded = false
                } else {
                    do {
                        let res = try await SimulatorService.shared.runXcrun(arguments: ["simctl", "push", targetDevice, bundleId, apnsURL.path])
                        if res.exitCode == 0 {
                            messages.append("Pushed APNs notification to \(bundleId)")
                        } else {
                            messages.append("APNs push failed: \(res.error)")
                            allSucceeded = false
                        }
                    } catch {
                        messages.append("APNs error: \(error.localizedDescription)")
                        allSucceeded = false
                    }
                }

            case .link(let linkURLs):
                for linkURL in linkURLs {
                    let result = await SimulatorService.shared.openURL(device: targetDevice, url: linkURL)
                    messages.append(result.message)
                    if !result.isSuccess { allSucceeded = false }
                }

            case .generalDocument(let docURLs):
                if let bundleId = targetBundleId, !bundleId.isEmpty {
                    let result = await SimulatorService.shared.copyFilesToApp(device: targetDevice, bundleId: bundleId, fileURLs: docURLs)
                    messages.append(result.message)
                    if !result.isSuccess { allSucceeded = false }
                } else {
                    // Import directly into Simulator's Files app ("On My iPhone")
                    let result = await SimulatorService.shared.copyFilesToFilesApp(device: targetDevice, fileURLs: docURLs)
                    messages.append(result.message)
                    if !result.isSuccess { allSucceeded = false }
                }
            }
        }

        let summary = messages.joined(separator: " • ")
        return allSucceeded ? .success(summary) : .failure(summary)
    }

    private func extractURLFromShortcutFile(url: URL) -> URL? {
        if let data = try? Data(contentsOf: url) {
            // Check if .webloc plist
            if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let str = plist["URL"] as? String,
               let target = URL(string: str) {
                return target
            }
            // Check if INI-style .url file
            if let str = String(data: data, encoding: .utf8) {
                for line in str.split(whereSeparator: \.isNewline) {
                    if line.uppercased().hasPrefix("URL=") {
                        let targetStr = String(line.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if let target = URL(string: targetStr) {
                            return target
                        }
                    }
                }
            }
        }
        return nil
    }

    private func extractBundleIdFromAPNS(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bundle = json["Simulator Target Bundle"] as? String else {
            return nil
        }
        return bundle
    }
}
