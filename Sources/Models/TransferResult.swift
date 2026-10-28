import Foundation

public enum TransferStatus: Equatable {
    case idle
    case inProgress(String)
    case success(String)
    case failure(String)
}

public struct TransferResult {
    public let isSuccess: Bool
    public let message: String

    public init(isSuccess: Bool, message: String) {
        self.isSuccess = isSuccess
        self.message = message
    }

    public static func success(_ message: String) -> TransferResult {
        TransferResult(isSuccess: true, message: message)
    }

    public static func failure(_ message: String) -> TransferResult {
        TransferResult(isSuccess: false, message: message)
    }
}
