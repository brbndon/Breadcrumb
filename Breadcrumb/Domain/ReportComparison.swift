import Foundation

struct ResolvedPeriods: Equatable, Sendable {
    let current: Range<Date>
    let previous: Range<Date>?
    let asOf: Date
}
