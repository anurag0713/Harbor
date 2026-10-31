import Foundation

/// Where a queued item will be sent inside the simulator.
public enum QueueItemDestination: Equatable, Sendable, Hashable {
    /// Smart routing by file type — current default behaviour, zero UX change.
    case auto
    /// Simulator Photos library via `simctl addmedia`.
    case photos
    /// Files app ("On My iPhone") storage.
    case filesApp
    /// A specific installed app's Documents container.
    case appDocuments(bundleId: String)

    // MARK: - Display helpers

    /// Short label used in the chip and popover.
    public var chipLabel: String {
        switch self {
        case .auto:                     return "Auto"
        case .photos:                   return "Photos"
        case .filesApp:                 return "Files"
        case .appDocuments:             return "App"   // caller replaces with display name
        }
    }

    /// SF Symbol name for the chip icon.
    public var systemImage: String {
        switch self {
        case .auto:                     return "wand.and.stars"
        case .photos:                   return "photo.on.rectangle.fill"
        case .filesApp:                 return "folder.fill"
        case .appDocuments:             return "app.badge.fill"
        }
    }

    public var isAuto: Bool {
        if case .auto = self { return true }
        return false
    }

    /// The resolved bundle-id when destination is `.appDocuments`, nil otherwise.
    public var bundleId: String? {
        if case .appDocuments(let id) = self { return id }
        return nil
    }
}

// MARK: - Auto-resolution helper

extension QueueItemDestination {
    /// Given a queue item kind, returns what `.auto` resolves to at transfer time.
    public static func autoResolved(for kind: QueueItemKind) -> QueueItemDestination {
        switch kind {
        case .photo, .video: return .photos
        default:             return .filesApp
        }
    }
}
