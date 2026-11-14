import Foundation

/// Value-type snapshot of a `UsageEvent` used by pure report logic.
struct EventSample: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let kind: EventKind
    let displayName: String
    let bundleID: String?
    let host: String?
    var endedAt: Date? = nil
    /// Input has been idle past the threshold while the foreground app held a media assertion.
    var passive: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, timestamp, kind, displayName, bundleID, host, endedAt, passive
    }

    /// Identity used for switch/transition comparison. Bundle ID wins over display name.
    var nodeKey: String {
        switch kind {
        case .app: "app:\(bundleID ?? displayName)"
        case .site: "site:\(host ?? displayName)"
        }
    }
}

extension EventSample {
    /// Archives written before passive visits existed have no `passive` key.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            timestamp: try values.decode(Date.self, forKey: .timestamp),
            kind: try values.decode(EventKind.self, forKey: .kind),
            displayName: try values.decode(String.self, forKey: .displayName),
            bundleID: try values.decodeIfPresent(String.self, forKey: .bundleID),
            host: try values.decodeIfPresent(String.self, forKey: .host),
            endedAt: try values.decodeIfPresent(Date.self, forKey: .endedAt),
            passive: try values.decodeIfPresent(Bool.self, forKey: .passive) ?? false)
    }
}
