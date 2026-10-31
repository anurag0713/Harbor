import Foundation

public final class FileRouter {
    public static let shared = FileRouter()

    private let mediaExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "webp",
        "mp4", "mov", "m4v", "avi", "mkv"
    ]

    private init() {}

    // MARK: - Legacy category type (kept for any external callers)

    public enum FileCategory {
        case appBundle([URL])
        case media([URL])
        case apnsPayload(URL)
        case link([URL])
        case generalDocument([URL])
    }

    /// Smart categorisation by file extension — still available for external use.
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
        if !apps.isEmpty  { categories.append(.appBundle(apps)) }
        if !media.isEmpty { categories.append(.media(media)) }
        for apnsURL in apns { categories.append(.apnsPayload(apnsURL)) }
        if !links.isEmpty  { categories.append(.link(links)) }
        if !others.isEmpty { categories.append(.generalDocument(others)) }
        return categories
    }

    // MARK: - Primary transfer entry point

    /// Routes and transfers a batch of `QueueItem`s, respecting each item's `.destination`
    /// override.  Items with `.auto` destination use smart file-type routing.
    /// The `globalDocumentTarget` is applied to any `.auto` general-document items that
    /// don't have their own override — giving the user a batch shortcut from the footer.
    public func routeAndTransfer(
        items: [QueueItem],
        targetDevice: String = "booted",
        fallbackBundleId: String? = nil,
        globalDocumentTarget: QueueItemDestination = .auto
    ) async -> TransferResult {
        guard !items.isEmpty else {
            return .failure("No files to send")
        }

        // ── Build routing buckets ─────────────────────────────────────────────
        var appBundles: [URL]           = []
        var mediaBatch: [URL]           = []
        var filesAppBatch: [URL]        = []
        var appDocsBatch: [String: [URL]] = [:]  // bundleId → [URL]
        var linkBatch: [URL]            = []
        var apnsBatch: [URL]            = []

        for item in items {
            let url = item.url

            // Fixed-route item kinds — user cannot override these.
            switch item.kind {
            case .app:
                appBundles.append(url)
                continue
            case .apnsPayload:
                apnsBatch.append(url)
                continue
            case .link:
                // .link covers both real URLs and .webloc / .url shortcut files.
                if url.isFileURL {
                    // Webloc / .url file — extract the real URL, drop the file path.
                    if let realURL = extractURLFromShortcutFile(url: url) {
                        linkBatch.append(realURL)
                    }
                    // If extraction fails, silently skip (malformed shortcut file).
                } else {
                    linkBatch.append(url)
                }
                continue
            default:
                break
            }

            // Resolve the effective destination for this item.
            let effective = resolveDestination(for: item, globalDocumentTarget: globalDocumentTarget)

            switch effective {
            case .auto:
                // Should not reach here after resolveDestination, but guard anyway.
                filesAppBatch.append(url)
            case .photos:
                mediaBatch.append(url)
            case .filesApp:
                filesAppBatch.append(url)
            case .appDocuments(let bundleId):
                appDocsBatch[bundleId, default: []].append(url)
            }
        }

        // ── Execute all buckets and collect results ───────────────────────────
        var messages: [String] = []
        var allSucceeded = true

        func record(_ result: TransferResult) {
            messages.append(result.message)
            if !result.isSuccess { allSucceeded = false }
        }

        // Install .app bundles
        for url in appBundles {
            record(await SimulatorService.shared.installApp(device: targetDevice, fileURL: url))
        }

        // Add media → Photos
        if !mediaBatch.isEmpty {
            record(await SimulatorService.shared.addMedia(device: targetDevice, fileURLs: mediaBatch))
        }

        // Copy to Files app
        if !filesAppBatch.isEmpty {
            record(await SimulatorService.shared.copyFilesToFilesApp(device: targetDevice, fileURLs: filesAppBatch))
        }

        // Copy to specific app Documents — resolve container fresh for each bundle.
        for (bundleId, urls) in appDocsBatch {
            record(await SimulatorService.shared.copyFilesToApp(device: targetDevice, bundleId: bundleId, fileURLs: urls))
        }

        // Open links / deep-links
        for url in linkBatch {
            record(await SimulatorService.shared.openURL(device: targetDevice, url: url))
        }

        // Push APNs payloads
        for url in apnsBatch {
            let bundleId = fallbackBundleId ?? (extractBundleIdFromAPNS(url: url) ?? "")
            if bundleId.isEmpty {
                messages.append("APNs dropped but no target bundle ID found")
                allSucceeded = false
            } else {
                do {
                    let res = try await SimulatorService.shared.runXcrun(
                        arguments: ["simctl", "push", targetDevice, bundleId, url.path]
                    )
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
        }

        let summary = messages.joined(separator: " • ")
        return allSucceeded ? .success(summary) : .failure(summary)
    }

    // MARK: - Destination resolution

    /// Resolves the effective destination for a single item.
    private func resolveDestination(
        for item: QueueItem,
        globalDocumentTarget: QueueItemDestination
    ) -> QueueItemDestination {
        // 1. Per-item explicit override wins.
        if !item.destination.isAuto {
            return item.destination
        }

        // 2. Global document target applies to general documents only.
        if item.kind == .generalDocument && !globalDocumentTarget.isAuto {
            return globalDocumentTarget
        }

        // 3. Smart auto-routing by file type.
        return QueueItemDestination.autoResolved(for: item.kind)
    }

    // MARK: - Private helpers

    private func extractURLFromShortcutFile(url: URL) -> URL? {
        if let data = try? Data(contentsOf: url) {
            // XML plist .webloc
            if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let str = plist["URL"] as? String,
               let target = URL(string: str) {
                return target
            }
            // INI-style .url file
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
