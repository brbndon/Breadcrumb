import Foundation
import SwiftData

enum EventKind: String, Codable, Sendable {
    case app
    case site
}

/// A single change of the frontmost app (or site). Stored locally only.
@Model
final class UsageEvent {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var kindRaw: String
    var displayName: String
    var bundleID: String?
    var host: String?
    var endedAt: Date?

    #Index<UsageEvent>([\.timestamp])

    var kind: EventKind { EventKind(rawValue: kindRaw) ?? .app }

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        kind: EventKind = .app,
        displayName: String,
        bundleID: String? = nil,
        host: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kindRaw = kind.rawValue
        self.displayName = displayName
        self.bundleID = bundleID
        self.host = host
    }

    var sample: EventSample {
        EventSample(
            id: id, timestamp: timestamp, kind: kind, displayName: displayName, bundleID: bundleID,
            host: host, endedAt: endedAt)
    }
}
