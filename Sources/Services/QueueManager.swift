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

    private init() {}

    public func add(urls: [URL]) {
        let expanded = expandDirectories(urls)
        for url in expanded {
            // Avoid duplicate path
            if !items.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                items.append(QueueItem(url: url))
            }
        }
    }

    private func expandDirectories(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default

        for url in urls {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                // If it is an .app bundle or package, do NOT expand inside it
                let ext = url.pathExtension.lowercased()
                if ext == "app" || ext == "framework" {
                    result.append(url)
                    continue
                }
                // Recursively gather files
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
        totalCount = items.count
        completedCount = 0
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
        completedCount = totalCount
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
