import Foundation

enum HistoryKindFilter: String, CaseIterable, Equatable, Sendable {
    case all = "All"
    case apps = "Apps"
    case sites = "Sites"
}

enum ReportSort: String, CaseIterable, Equatable, Sendable {
    case visits = "Visits"
    case estimatedTime = "Estimated time"
}

struct HistoryFilter: Equatable, Sendable {
    var text = ""
    var kind: HistoryKindFilter = .all
    var nodeKey: String?
    var isActive: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || kind != .all || nodeKey != nil
    }

    func matches(_ event: EventSample) -> Bool {
        guard
            kind == .all || (kind == .apps && event.kind == .app) || (kind == .sites && event.kind == .site),
            nodeKey == nil || nodeKey == event.nodeKey
        else { return false }
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || event.displayName.localizedStandardContains(term)
            || event.bundleID?.localizedStandardContains(term) == true
            || event.host?.localizedStandardContains(term) == true
    }
}

struct HistoryQuery: Equatable, Sendable {
    let interval: Range<Date>
    let filter: HistoryFilter
}

struct JourneyCursor: Equatable, Sendable {
    let timestamp: Date
    let id: UUID
    func includes(_ event: EventSample) -> Bool {
        event.timestamp < timestamp || (event.timestamp == timestamp && event.id.uuidString < id.uuidString)
    }
}

struct JourneyPage: Sendable {
    let rows: [JourneyRow]
    let nextCursor: JourneyCursor?
}
