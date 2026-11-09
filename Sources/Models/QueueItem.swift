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
    /// Short, concise failure label for row subtitles (e.g. "macOS app (requires iOS build)")
    public var failureReason: String?
    /// Full diagnostic explanation for tooltips and accessibility
    public var failureMessage: String?
    /// Where this item will be sent. Defaults to `.auto` (smart routing by file type).
    public var destination: QueueItemDestination = .auto

    public init(url: URL) {
        self.id = UUID()
        self.url = url
        self.kind = QueueItemKind(url: url)
        self.failureReason = nil
        self.failureMessage = nil
    }

    /// Whether this item supports a destination chip (apps/links are always fixed-route).
    public var supportsDestinationOverride: Bool {
        switch kind {
        case .app, .link, .apnsPayload: return false
        default: return true
        }
    }

    public var name: String {
        if kind == .link {
            return url.absoluteString
        }
        return url.lastPathComponent
    }

    /// Contextual SF Symbol for the file or resource.
    public var iconSystemName: String {
        guard kind == .generalDocument, url.isFileURL else {
            return kind.systemImage
        }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return "doc.richtext.fill"
        case "swift", "c", "cpp", "h", "m", "js", "ts", "json", "py", "sh":
            return "chevron.left.forwardslash.chevron.right"
        case "zip", "tar", "gz", "bz2", "xz":
            return "doc.zipper"
        case "mp3", "m4a", "wav", "aac":
            return "music.note"
        case "txt", "md", "markdown", "log":
            return "doc.plaintext.fill"
        default:
            return kind.systemImage
        }
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
