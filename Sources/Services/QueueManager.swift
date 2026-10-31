import Foundation
import Combine
import SwiftUI

@MainActor
public final class QueueManager: ObservableObject {
    public static let shared = QueueManager()

    @Published public private(set) var items: [QueueItem] = []
    @Published public private(set) var isSending: Bool = false
    @Published public private(set) var statusMessage: String?
    @Published public private(set) var isSuccess: Bool = true
    @Published public private(set) var completedCount: Int = 0
    @Published public private(set) var totalCount: Int = 0

    public enum BatchDestinationState: Equatable {
        case none
        case uniform(QueueItemDestination)
        case mixed
    }

    /// The collective destination state of all eligible items in the queue.
    public var batchDestinationState: BatchDestinationState {
        let eligible = items.filter(\.supportsDestinationOverride)
        guard !eligible.isEmpty else { return .none }
        let first = eligible[0].destination
        if eligible.allSatisfy({ $0.destination == first }) {
            return .uniform(first)
        } else {
            return .mixed
        }
    }

    private var activeBatchIDs: Set<UUID> = []

    private init() {}

    // MARK: - Queue mutation

    public func add(urls: [URL]) {
        let expanded = expandDirectories(urls)

        // If all existing items currently share an explicit uniform destination,
        // new items adopt it too for a seamless workflow.
        let defaultDest: QueueItemDestination
        if case .uniform(let dest) = batchDestinationState, !dest.isAuto {
            defaultDest = dest
        } else {
            defaultDest = .auto
        }

        for url in expanded {
            if !items.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                var newItem = QueueItem(url: url)
                if newItem.supportsDestinationOverride {
                    newItem.destination = defaultDest
                }
                items.append(newItem)
            }
        }
    }

    public func remove(id: UUID) {
        guard !activeBatchIDs.contains(id) else { return }
        items.removeAll { $0.id == id }
    }

    public func clear() {
        guard !isSending else { return }
        items.removeAll()
        statusMessage = nil
    }

    /// Updates the destination for a single queued item.
    public func setDestination(_ destination: QueueItemDestination, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].destination = destination
    }

    /// Updates the destination for all eligible items in the queue (e.g. from the batch dropdown).
    public func setDestinationForAll(_ destination: QueueItemDestination) {
        for index in items.indices {
            if items[index].supportsDestinationOverride {
                // If destination is .photos, only set it for media files.
                if destination == .photos && (items[index].kind != .photo && items[index].kind != .video) {
                    continue
                }
                items[index].destination = destination
            }
        }
    }

    // MARK: - Transfer

    public func sendAll(targetDevice: String, targetBundleId: String? = nil) async {
        guard !items.isEmpty, !isSending else { return }

        isSending = true
        totalCount = items.count
        completedCount = 0
        statusMessage = "Sending \(items.count) item(s)..."
        isSuccess = true

        // Snapshot the batch by priority order; items added after this point are NOT in this batch.
        let sortedItems = items.sorted { $0.kind.priorityOrder < $1.kind.priorityOrder }
        let batchItemIDs = Set(sortedItems.map(\.id))
        activeBatchIDs = batchItemIDs

        let result = await FileRouter.shared.routeAndTransfer(
            items: sortedItems,
            targetDevice: targetDevice,
            fallbackBundleId: targetBundleId
        )

        isSending = false
        activeBatchIDs.removeAll()
        isSuccess = result.isSuccess
        completedCount = totalCount
        statusMessage = result.message

        if result.isSuccess {
            // Only remove items that were part of this batch — items dropped during
            // the transfer are preserved for the next send.
            items.removeAll { batchItemIDs.contains($0.id) }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self else { return }
                if self.statusMessage == result.message {
                    self.statusMessage = nil
                }
            }
        }
    }

    // MARK: - Private helpers

    private func expandDirectories(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default

        for url in urls {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let ext = url.pathExtension.lowercased()
                if ext == "app" || ext == "framework" {
                    result.append(url)
                    continue
                }
                if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                    for case let fileURL as URL in enumerator {
                        if let res = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]), res.isRegularFile == true {
                            result.append(fileURL)
                        }
                    }
                }
            } else {
                result.append(url)
            }
        }
        return result
    }
}
