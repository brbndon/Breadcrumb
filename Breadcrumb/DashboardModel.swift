import Foundation
import Observation

@MainActor
@Observable
final class DashboardModel {
    var range: DateRange = .today
    var customStart = Date.now
    var customEnd = Date.now
    private(set) var periods: ResolvedPeriods?
    private(set) var summary = ScreenTimeSummary()
    private(set) var previous: ScreenTimeSummary?
    /// Range and periods that produced `summary`; `periods` moves ahead while loading.
    private(set) var shown: (range: DateRange, periods: ResolvedPeriods)?
    private(set) var isLoading = false
    private(set) var error: String?
    /// The summary on screen no longer matches the selection: a load is running or the last one failed.
    var isStale: Bool { shown != nil && (isLoading || error != nil) }
    private var revision: Int?
    private var generation = 0
    private var task: Task<Void, Never>?
    private var applied: (DateRange, Date, Date)?
    private let query: @MainActor (Range<Date>, Date, Calendar) async throws -> ScreenTimeSummary

    init(query: @escaping @MainActor (Range<Date>, Date, Calendar) async throws -> ScreenTimeSummary) {
        self.query = query
    }
    convenience init(store: UsageStore) {
        let service = HistoryQueryService(store: store)
        self.init { try await service.screenTime(in: $0, asOf: $1, calendar: $2) }
    }
    func refresh(now: Date = .now, calendar: Calendar = .current) {
        do {
            let periods = try range.resolve(
                now: now, calendar: calendar, customStart: customStart, customEnd: customEnd)
            applied = (range, customStart, customEnd)
            load(periods, range: range, calendar: calendar)
        } catch { self.error = error.localizedDescription }
    }
    private func load(_ periods: ResolvedPeriods, range: DateRange, calendar: Calendar) {
        task?.cancel()
        generation += 1
        let token = generation
        self.periods = periods
        isLoading = true
        error = nil
        task = Task { [weak self, query] in
            do {
                let summary = try await query(periods.current, periods.asOf, calendar)
                let previous: ScreenTimeSummary?
                if let interval = periods.previous {
                    previous = try await query(interval, periods.asOf, calendar)
                } else {
                    previous = nil
                }
                try Task.checkCancellation()
                guard let self, token == self.generation else { return }
                self.summary = summary
                self.previous = previous
                self.shown = (range, periods)
                self.isLoading = false
            } catch {
                guard let self, token == self.generation, !Task.isCancelled else { return }
                self.error = "Screen time could not be loaded. Retry refresh."
                self.isLoading = false
            }
        }
    }
    private func refreshApplied(now: Date, calendar: Calendar) {
        guard let applied else {
            refresh(now: now, calendar: calendar)
            return
        }
        do {
            load(
                try applied.0.resolve(
                    now: now, calendar: calendar, customStart: applied.1, customEnd: applied.2),
                range: applied.0, calendar: calendar)
        } catch { self.error = error.localizedDescription }
    }
    func storeChanged(revision: Int, now: Date = .now) {
        guard self.revision != revision else { return }
        self.revision = revision
        refreshApplied(now: now, calendar: .current)
    }
    func dayChanged(now: Date, calendar: Calendar = .current) {
        guard let periods, !calendar.isDate(now, inSameDayAs: periods.asOf) else { return }
        refreshApplied(now: now, calendar: calendar)
    }
    func configureHistory(_ explorer: HistoryExplorer) {
        guard let applied, let periods else { return }
        explorer.range = applied.0
        explorer.customStart = applied.1
        explorer.customEnd = applied.2
        explorer.refresh(now: periods.asOf)
    }
    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        isLoading = false
    }
}
