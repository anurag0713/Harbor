import Foundation

public final class FileRouter {
    public static let shared = FileRouter()

    private let mediaExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "webp",
        "mp4", "mov", "m4v", "avi", "mkv"
    ]

    private init() {}

    public enum FileCategory {
        case media([URL])
        case apnsPayload(URL)
        case generalDocument([URL])
    }

    public func categorize(urls: [URL]) -> [FileCategory] {
        var media: [URL] = []
        var others: [URL] = []
        var apns: [URL] = []

        for url in urls {
            let ext = url.pathExtension.lowercased()
            if ext == "apns" {
                apns.append(url)
            } else if mediaExtensions.contains(ext) {
                media.append(url)
            } else {
                others.append(url)
            }
        }

        var categories: [FileCategory] = []
        if !media.isEmpty {
            categories.append(.media(media))
        }
        for apnsURL in apns {
            categories.append(.apnsPayload(apnsURL))
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

            case .generalDocument(let docURLs):
                if let bundleId = targetBundleId, !bundleId.isEmpty {
                    let result = await SimulatorService.shared.copyFilesToApp(device: targetDevice, bundleId: bundleId, fileURLs: docURLs)
                    messages.append(result.message)
                    if !result.isSuccess { allSucceeded = false }
                } else {
                    // Try to add as media anyway (some simulators accept files in Photos/Files)
                    let result = await SimulatorService.shared.addMedia(device: targetDevice, fileURLs: docURLs)
                    if result.isSuccess {
                        messages.append("Imported \(docURLs.count) file(s)")
                    } else {
                        messages.append("Non-media files require an active app bundle ID to target Documents")
                        allSucceeded = false
                    }
                }
            }
        }

        let summary = messages.joined(separator: " • ")
        return allSucceeded ? .success(summary) : .failure(summary)
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
