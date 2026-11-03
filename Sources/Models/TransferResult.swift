import Foundation

public enum TransferStatus: Equatable {
    case idle
    case inProgress(String)
    case success(String)
    case failure(String)
}

public struct ItemTransferError: Sendable, Hashable {
    public let shortReason: String
    public let detailedExplanation: String
    public let category: Category

    public enum Category: Sendable, Hashable {
        case macOSApp
        case deviceOnlyApp
        case missingExecutable
        case incompatibleArchitecture
        case unsupportedURLScheme(scheme: String)
        case photosUnsupported
        case general(String)
    }

    public init(shortReason: String, detailedExplanation: String, category: Category) {
        self.shortReason = shortReason
        self.detailedExplanation = detailedExplanation
        self.category = category
    }

    public static func macOSApp(name: String) -> ItemTransferError {
        ItemTransferError(
            shortReason: "macOS app (requires iOS build)",
            detailedExplanation: "“\(name)” is a macOS app and cannot be installed on iOS Simulator. Simulators require an iOS Simulator build (.app).",
            category: .macOSApp
        )
    }

    public static func unsupportedScheme(scheme: String) -> ItemTransferError {
        ItemTransferError(
            shortReason: "No app for scheme “\(scheme)”",
            detailedExplanation: "No app is installed on the simulator to handle the “\(scheme)” URL scheme (error -10814).",
            category: .unsupportedURLScheme(scheme: scheme)
        )
    }

    public static func photosError(reason: String) -> ItemTransferError {
        ItemTransferError(
            shortReason: "Photos import error",
            detailedExplanation: reason,
            category: .photosUnsupported
        )
    }

    public static func general(short: String, detailed: String) -> ItemTransferError {
        ItemTransferError(
            shortReason: short,
            detailedExplanation: detailed,
            category: .general(short)
        )
    }
}

public struct TransferResult: Sendable {
    public let isSuccess: Bool
    public let message: String
    public let errorDetail: ItemTransferError?

    public init(isSuccess: Bool, message: String, errorDetail: ItemTransferError? = nil) {
        self.isSuccess = isSuccess
        self.message = message
        self.errorDetail = errorDetail
    }

    public static func success(_ message: String) -> TransferResult {
        TransferResult(isSuccess: true, message: message, errorDetail: nil)
    }

    public static func failure(_ message: String, detail: ItemTransferError? = nil) -> TransferResult {
        TransferResult(isSuccess: false, message: message, errorDetail: detail)
    }
}

public struct BatchTransferResult: Sendable {
    public let successfulItemIDs: Set<UUID>
    public let failedItemIDs: Set<UUID>
    public let successMessages: [String]
    public let itemErrors: [UUID: ItemTransferError]

    public init(
        successfulItemIDs: Set<UUID> = [],
        failedItemIDs: Set<UUID> = [],
        successMessages: [String] = [],
        itemErrors: [UUID: ItemTransferError] = [:]
    ) {
        self.successfulItemIDs = successfulItemIDs
        self.failedItemIDs = failedItemIDs
        self.successMessages = successMessages
        self.itemErrors = itemErrors
    }

    public var isSuccess: Bool {
        failedItemIDs.isEmpty
    }

    public var successSummary: String? {
        guard !successMessages.isEmpty else { return nil }
        return successMessages.joined(separator: " • ")
    }

    /// Smart aggregation of errors to prevent repetitive bullet walls in the compact footer.
    public var errorSummary: String? {
        let errors = failedItemIDs.compactMap { itemErrors[$0] }
        guard !errors.isEmpty else { return nil }

        // If items were stopped by the user, report cleanly
        let stoppedCount = errors.filter { $0.shortReason == "Stopped by user" }.count
        if stoppedCount > 0 {
            if stoppedCount == errors.count {
                let label = stoppedCount == 1 ? "1 item" : "\(stoppedCount) items"
                return "Transfer stopped (\(label) remaining)."
            } else {
                return "Transfer stopped (\(stoppedCount) remaining, \(errors.count - stoppedCount) failed)."
            }
        }

        // If only 1 item failed: show the full diagnostic sentence.
        if errors.count == 1 {
            return errors[0].detailedExplanation
        }

        // Multiple items failed: Check if all share the same failure category.
        let categories = errors.map(\.category)
        let firstCategory = categories[0]
        let allSame = categories.allSatisfy { $0 == firstCategory }

        if allSame {
            switch firstCategory {
            case .macOSApp:
                return "\(errors.count) macOS apps cannot be installed on iOS Simulator. Simulators require iOS Simulator builds (.app)."
            case .unsupportedURLScheme:
                return "\(errors.count) links could not be opened (no matching apps installed on simulator)."
            case .photosUnsupported:
                return "\(errors.count) files could not be imported into Photos."
            case .deviceOnlyApp:
                return "\(errors.count) apps were built for iOS devices and cannot run on simulator."
            case .missingExecutable:
                return "\(errors.count) app bundles are missing their executable binary."
            case .incompatibleArchitecture:
                return "\(errors.count) apps have incompatible architecture for this simulator."
            case .general(let desc):
                return "\(errors.count) items failed: \(desc)"
            }
        }

        // Multiple items failed with mixed categories: summarize by category counts.
        var counts: [String: Int] = [:]
        for err in errors {
            switch err.category {
            case .macOSApp:
                counts["macOS app", default: 0] += 1
            case .unsupportedURLScheme:
                counts["unsupported link", default: 0] += 1
            case .photosUnsupported:
                counts["media file", default: 0] += 1
            case .deviceOnlyApp:
                counts["device app", default: 0] += 1
            case .missingExecutable:
                counts["invalid bundle", default: 0] += 1
            case .incompatibleArchitecture:
                counts["architecture mismatch", default: 0] += 1
            case .general(let short):
                counts[short, default: 0] += 1
            }
        }

        let breakdown = counts.sorted { $0.key < $1.key }.map { name, count in
            count == 1 ? "1 \(name)" : "\(count) \(name)s"
        }.joined(separator: ", ")

        return "\(errors.count) items could not be sent: \(breakdown)."
    }
}
