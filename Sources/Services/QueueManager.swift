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

    private init() {}

    public func add(urls: [URL]) {
        for url in urls {
            // Avoid duplicate path
            if !items.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                items.append(QueueItem(url: url))
            }
        }
    }

    public func remove(id: UUID) {
        guard !isSending else { return }
        items.removeAll { $0.id == id }
    }

    public func clear() {
        guard !isSending else { return }
        items.removeAll()
        statusMessage = nil
    }

    public func sendAll(targetDevice: String, targetBundleId: String? = nil) async {
        guard !items.isEmpty, !isSending else { return }

        isSending = true
        statusMessage = "Sending \(items.count) item(s)..."
        isSuccess = true

        // Sort items by priority order (e.g. apps first)
        let sortedItems = items.sorted { $0.kind.priorityOrder < $1.kind.priorityOrder }
        let urls = sortedItems.map(\.url)

        let result = await FileRouter.shared.routeAndTransfer(
            urls: urls,
            targetDevice: targetDevice,
            targetBundleId: targetBundleId
        )

        isSending = false
        isSuccess = result.isSuccess
        statusMessage = result.message

        if result.isSuccess {
            items.removeAll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if self.statusMessage == result.message {
                    self.statusMessage = nil
                }
            }
        }
    }
}
