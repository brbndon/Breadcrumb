import Foundation
import Observation

@MainActor
@Observable
final class HistoryExplorer {
    var range: DateRange = .today
    var customStart = Date.now
    var customEnd = Date.now
    var filter = HistoryFilter()
    var sort: ReportSort = .visits
    var showAllApps = false
    var showAllSites = false
    var comparisonEnabled = false
    private(set) var periods: ResolvedPeriods?
    private(set) var rows: [JourneyRow] = []
    private(set) var report = Report()
    private(set) var previousReport: Report?
    private(set) var isLoading = false
    private(set) var journeyError: String?
    private(set) var reportError: String?
    private(set) var periodError: String?
    private(set) var nextCursor: JourneyCursor?
    private var revision: Int?
    private var generation = 0
    private var pageTask: Task<Void, Never>?
    private let page: @MainActor (HistoryQuery, JourneyCursor?, Int) async throws -> JourneyPage
    private let buildReport: @MainActor (Range<Date>) throws -> Report

    init(
        page: @escaping @MainActor (HistoryQuery, JourneyCursor?, Int) async throws -> JourneyPage,
        report: @escaping @MainActor (Range<Date>) throws -> Report
    ) {
        self.page = page
        self.buildReport = report
    }

    convenience init(store: UsageStore) {
        let service = HistoryQueryService(store: store)
        self.init(
            page: { query, cursor, limit in
                try service.journeyPage(for: query, before: cursor, limit: limit)
            }, report: { try store.report(in: $0) })
    }

    func refresh(now: Date = .now, calendar: Calendar = .current) {
        do {
            periods = try range.resolve(
                now: now, calendar: calendar, customStart: customStart, customEnd: customEnd)
            periodError = nil
        } catch {
            periodError = error.localizedDescription
            return
        }
        updateReports()
        reloadJourney()
    }

    func updateReports() {
        guard let periods else { return }
        do {
            let current = try buildReport(periods.current)
            let previous = try comparisonEnabled ? periods.previous.map(buildReport) : nil
            report = current
            previousReport = previous
            reportError = nil
        } catch {
            reportError = "Report unavailable. History has been kept."
            previousReport = nil
        }
    }

    func storeChanged(revision: Int, now: Date = .now) {
        guard self.revision != revision else { return }
        self.revision = revision
        refresh(now: now)
    }

    func dayChanged(now: Date, calendar: Calendar = .current) {
        guard let periods, !calendar.isDate(periods.asOf, inSameDayAs: now) else { return }
        refresh(now: now, calendar: calendar)
    }

    func reloadJourney(debounce: Bool = false) {
        generation += 1
        pageTask?.cancel()
        rows = []
        nextCursor = nil
        journeyError = nil
        requestPage(append: false, debounce: debounce)
    }

    func loadOlder() {
        guard !isLoading, nextCursor != nil else { return }
        requestPage(append: true)
    }

    func retryJourney() { requestPage(append: !rows.isEmpty) }

    func clearFilters() {
        filter = HistoryFilter()
        reloadJourney()
    }

    func stop() {
        generation += 1
        pageTask?.cancel()
        pageTask = nil
        isLoading = false
    }

    private func requestPage(append: Bool, debounce: Bool = false) {
        guard let periods else { return }
        let query = HistoryQuery(interval: periods.current, filter: filter)
        let cursor = append ? nextCursor : nil
        let token = generation
        isLoading = true
        journeyError = nil
        pageTask = Task { [weak self, page] in
            do {
                if debounce { try await Task.sleep(for: .milliseconds(250)) }
                try Task.checkCancellation()
                let result = try await page(query, cursor, 100)
                guard let self, self.generation == token, !Task.isCancelled else { return }
                if append { self.rows += result.rows } else { self.rows = result.rows }
                self.nextCursor = result.nextCursor
                self.isLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.isLoading = false
                self.journeyError = "Journey unavailable. History has been kept."
            }
        }
    }
}
