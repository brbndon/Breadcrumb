import Foundation

/// Value-type snapshot of a `UsageEvent` used by pure report logic.
struct EventSample: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let kind: EventKind
    let displayName: String
    let bundleID: String?
    let host: String?

    /// Identity used for switch/transition comparison. Bundle ID wins over display name.
    var nodeKey: String {
        switch kind {
        case .app: "app:\(bundleID ?? displayName)"
        case .site: "site:\(host ?? displayName)"
        }
    }
}
