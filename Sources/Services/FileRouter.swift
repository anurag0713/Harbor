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
    /// override. Items with `.auto` destination use smart file-type routing.
    /// The `globalDocumentTarget` is applied to any `.auto` general-document items that
    /// don't have their own override — giving the user a batch shortcut from the footer.
    public func routeAndTransfer(
        items: [QueueItem],
        targetDevice: String = "booted",
        fallbackBundleId: String? = nil,
        globalDocumentTarget: QueueItemDestination = .auto,
        onItemStart: (@MainActor (UUID) -> Void)? = nil,
        onItemSuccess: (@MainActor (UUID) -> Void)? = nil
    ) async -> BatchTransferResult {
        guard !items.isEmpty else {
            return BatchTransferResult(
                successfulItemIDs: [],
                failedItemIDs: [],
                successMessages: [],
                itemErrors: [:]
            )
        }

        // ── Build routing buckets with item tracking ─────────────────────────
        var appItems: [QueueItem]               = []
        var mediaItems: [QueueItem]             = []
        var filesAppItems: [QueueItem]          = []
        var appDocsItems: [String: [QueueItem]] = [:]  // bundleId → [QueueItem]
        var linkItems: [QueueItem]              = []
        var apnsItems: [QueueItem]              = []

        for item in items {
            // Fixed-route item kinds — user cannot override these.
            switch item.kind {
            case .app:
                appItems.append(item)
                continue
            case .apnsPayload:
                apnsItems.append(item)
                continue
            case .link:
                linkItems.append(item)
                continue
            default:
                break
            }

            // Resolve the effective destination for this item.
            let effective = resolveDestination(for: item, globalDocumentTarget: globalDocumentTarget)

            switch effective {
            case .auto:
                filesAppItems.append(item)
            case .photos:
                mediaItems.append(item)
            case .filesApp:
                filesAppItems.append(item)
            case .appDocuments(let bundleId):
                appDocsItems[bundleId, default: []].append(item)
            }
        }

        var successfulItemIDs = Set<UUID>()
        var failedItemIDs = Set<UUID>()
        var successMessages: [String] = []
        var itemErrors: [UUID: ItemTransferError] = [:]

        // 1. Install .app bundles (individually tracked)
        for item in appItems {
            if Task.isCancelled {
                failedItemIDs.insert(item.id)
                itemErrors[item.id] = ItemTransferError.general(short: "Stopped by user", detailed: "Transfer was stopped.")
                continue
            }
            await onItemStart?(item.id)
            let res = await SimulatorService.shared.installApp(device: targetDevice, fileURL: item.url)
            if res.isSuccess {
                successfulItemIDs.insert(item.id)
                successMessages.append(res.message)
                await onItemSuccess?(item.id)
            } else {
                failedItemIDs.insert(item.id)
                itemErrors[item.id] = res.errorDetail ?? ItemTransferError.general(short: res.message, detailed: res.message)
            }
        }

        // 2. Add media → Photos (progressive chunking with live success callbacks)
        if !mediaItems.isEmpty {
            let mediaRes = await SimulatorService.shared.addMediaProgressive(
                device: targetDevice,
                items: mediaItems,
                onItemStart: onItemStart,
                onItemSuccess: onItemSuccess
            )
            successfulItemIDs.formUnion(mediaRes.succeededIDs)
            failedItemIDs.formUnion(mediaRes.failedIDs)
            for (id, err) in mediaRes.errors {
                itemErrors[id] = err
            }
            if !mediaRes.succeededIDs.isEmpty {
                let count = mediaRes.succeededIDs.count
                let label = count == 1 ? "1 item" : "\(count) items"
                successMessages.append("Imported \(label) into Photos")
            }
        }

        // 3. Copy to Files app (progressive live copy)
        if !filesAppItems.isEmpty {
            let filesRes = await SimulatorService.shared.copyFilesToFilesAppProgressive(
                device: targetDevice,
                items: filesAppItems,
                onItemStart: onItemStart,
                onItemSuccess: onItemSuccess
            )
            successfulItemIDs.formUnion(filesRes.succeededIDs)
            failedItemIDs.formUnion(filesRes.failedIDs)
            for (id, err) in filesRes.errors {
                itemErrors[id] = err
            }
            if !filesRes.succeededIDs.isEmpty {
                let count = filesRes.succeededIDs.count
                let label = count == 1 ? "1 file" : "\(count) files"
                successMessages.append("Imported \(label) into Files app")
            }
        }

        // 4. Copy to specific app Documents (progressive live copy)
        for (bundleId, groupItems) in appDocsItems {
            let appRes = await SimulatorService.shared.copyFilesToAppProgressive(
                device: targetDevice,
                bundleId: bundleId,
                items: groupItems,
                onItemStart: onItemStart,
                onItemSuccess: onItemSuccess
            )
            successfulItemIDs.formUnion(appRes.succeededIDs)
            failedItemIDs.formUnion(appRes.failedIDs)
            for (id, err) in appRes.errors {
                itemErrors[id] = err
            }
            if !appRes.succeededIDs.isEmpty {
                let count = appRes.succeededIDs.count
                let label = count == 1 ? "1 file" : "\(count) files"
                successMessages.append("Copied \(label) into \(bundleId)")
            }
        }

        // 5. Open links / deep-links (individually tracked)
        for item in linkItems {
            if Task.isCancelled {
                failedItemIDs.insert(item.id)
                itemErrors[item.id] = ItemTransferError.general(short: "Stopped by user", detailed: "Transfer was stopped.")
                continue
            }
            let targetURL: URL
            if item.url.isFileURL {
                if let extracted = extractURLFromShortcutFile(url: item.url) {
                    targetURL = extracted
                } else {
                    failedItemIDs.insert(item.id)
                    let err = "Invalid link shortcut file “\(item.name)”"
                    itemErrors[item.id] = ItemTransferError.general(short: "Invalid shortcut", detailed: err)
                    continue
                }
            } else {
                targetURL = item.url
            }

            await onItemStart?(item.id)
            let res = await SimulatorService.shared.openURL(device: targetDevice, url: targetURL)
            if res.isSuccess {
                successfulItemIDs.insert(item.id)
                successMessages.append(res.message)
                await onItemSuccess?(item.id)
            } else {
                failedItemIDs.insert(item.id)
                itemErrors[item.id] = res.errorDetail ?? ItemTransferError.general(short: res.message, detailed: res.message)
            }
        }

        // 6. Push APNs payloads (individually tracked)
        for item in apnsItems {
            if Task.isCancelled {
                failedItemIDs.insert(item.id)
                itemErrors[item.id] = ItemTransferError.general(short: "Stopped by user", detailed: "Transfer was stopped.")
                continue
            }
            let bundleId = fallbackBundleId ?? (extractBundleIdFromAPNS(url: item.url) ?? "")
            if bundleId.isEmpty {
                let err = "APNs file “\(item.name)” has no target bundle ID"
                failedItemIDs.insert(item.id)
                itemErrors[item.id] = ItemTransferError.general(short: "No bundle ID", detailed: err)
            } else {
                do {
                    await onItemStart?(item.id)
                    let res = try await SimulatorService.shared.runXcrun(
                        arguments: ["simctl", "push", targetDevice, bundleId, item.url.path]
                    )
                    if res.exitCode == 0 {
                        successfulItemIDs.insert(item.id)
                        successMessages.append("Pushed APNs notification to \(bundleId)")
                        await onItemSuccess?(item.id)
                    } else {
                        let concise = SimulatorService.conciseMessage(res.error)
                        let err = "APNs push failed: \(concise)"
                        failedItemIDs.insert(item.id)
                        itemErrors[item.id] = ItemTransferError.general(short: "Push failed", detailed: err)
                    }
                } catch {
                    let err = "APNs error: \(error.localizedDescription)"
                    failedItemIDs.insert(item.id)
                    itemErrors[item.id] = ItemTransferError.general(short: "Push error", detailed: err)
                }
            }
        }

        return BatchTransferResult(
            successfulItemIDs: successfulItemIDs,
            failedItemIDs: failedItemIDs,
            successMessages: successMessages,
            itemErrors: itemErrors
        )
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
