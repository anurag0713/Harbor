import AppKit
import Foundation

@MainActor
public final class ClipboardService: ObservableObject {
    public static let shared = ClipboardService()

    @Published public private(set) var currentHostPreview: String = ""
    @Published public private(set) var lastSyncMessage: String?
    @Published public private(set) var isSyncing: Bool = false

    private init() {
        updateHostPreview()
    }

    public func updateHostPreview() {
        if let string = NSPasteboard.general.string(forType: .string) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 40 {
                currentHostPreview = String(trimmed.prefix(37)) + "..."
            } else {
                currentHostPreview = trimmed.isEmpty ? "(Empty clipboard)" : trimmed
            }
        } else {
            currentHostPreview = "(Non-text content)"
        }
    }

    /// Push text from Mac host pasteboard into the active simulator
    public func pushToSimulator(targetDevice: String = "booted") async -> TransferResult {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            let err = TransferResult.failure("Mac clipboard is empty")
            lastSyncMessage = err.message
            return err
        }

        isSyncing = true
        let result = await SimulatorService.shared.pushClipboard(device: targetDevice, text: text)
        isSyncing = false
        lastSyncMessage = result.message
        return result
    }

    /// Pull text from active simulator pasteboard into Mac host pasteboard
    public func pullFromSimulator(targetDevice: String = "booted") async -> TransferResult {
        isSyncing = true
        let (text, result) = await SimulatorService.shared.pullClipboard(device: targetDevice)
        isSyncing = false

        if let text = text, !text.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            updateHostPreview()
            let success = TransferResult.success("Copied simulator clipboard to Mac")
            lastSyncMessage = success.message
            return success
        } else {
            lastSyncMessage = result.message
            return result
        }
    }
}
