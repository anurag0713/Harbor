import Foundation
import UniformTypeIdentifiers

public enum QueueItemKind: Sendable, Hashable {
    case app
    case photo
    case video
    case contact
    case apnsPayload
    case link
    case generalDocument

    public init(url: URL) {
        if !url.isFileURL {
            self = .link
            return
        }

        let ext = url.pathExtension.lowercased()
        if ext == "app" {
            self = .app
            return
        }
        if ext == "apns" {
            self = .apnsPayload
            return
        }
        if ext == "webloc" || ext == "url" {
            self = .link
            return
        }

        let type = UTType(filenameExtension: ext)
        if type?.conforms(to: .vCard) == true {
            self = .contact
        } else if type?.conforms(to: .image) == true {
            self = .photo
        } else if type?.conforms(to: .movie) == true {
            self = .video
        } else {
            self = .generalDocument
        }
    }

    public var title: String {
        switch self {
        case .app: return "App Bundle"
        case .photo: return "Photo"
        case .video: return "Video"
        case .contact: return "Contact"
        case .apnsPayload: return "Push APNs"
        case .link: return "Deep Link"
        case .generalDocument: return "Document"
        }
    }

    public var systemImage: String {
        switch self {
        case .app: return "app.badge.fill"
        case .photo: return "photo.fill"
        case .video: return "film.fill"
        case .contact: return "person.crop.circle.fill"
        case .apnsPayload: return "bell.badge.fill"
        case .link: return "link"
        case .generalDocument: return "doc.fill"
        }
    }

    public var priorityOrder: Int {
        switch self {
        case .app: return 0
        case .photo, .video, .contact, .generalDocument: return 1
        case .apnsPayload: return 2
        case .link: return 3
        }
    }
}

public struct QueueItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let kind: QueueItemKind
    public var failureMessage: String?

    public init(url: URL) {
        self.id = UUID()
        self.url = url
        self.kind = QueueItemKind(url: url)
        self.failureMessage = nil
    }

    public var name: String {
        if kind == .link {
            return url.absoluteString
        }
        return url.lastPathComponent
    }

    public var formattedSize: String {
        guard url.isFileURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return ""
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
