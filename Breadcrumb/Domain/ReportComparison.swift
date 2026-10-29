import Foundation

struct ResolvedPeriods: Equatable, Sendable {
    let current: Range<Date>
    let previous: Range<Date>?
    let asOf: Date
}

struct ReportComparison {
    let current: Report
    let previous: Report?

    func difference(_ metric: KeyPath<Report, Int>) -> Int? {
        guard current.hasRecordedHistory, let previous, previous.hasRecordedHistory else { return nil }
        return current[keyPath: metric] - previous[keyPath: metric]
    }

    static func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : value < 0 ? "−\(abs(value))" : "0"
    }
}

extension Report {
    var hasRecordedHistory: Bool { !topApps.isEmpty || !topSites.isEmpty }
}
