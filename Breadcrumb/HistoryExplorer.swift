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
    private(set) var selectionRevision = 0
    private(set) var selectedName: String?
    private var reportAnchor: Date?
    var showAllApps = false
    var showAllSites = false
    var comparisonEnabled = false
    private(set) var periods: ResolvedPeriods?
    private(set) var rows: [JourneyRow] = []
    private(set) var report = Report()
    private(set) var previousReport: Report?
    private(set) var isLoading = false
    private(set) var isReporting = false
    private(set) var journeyError: String?
    private(set) var reportError: String?
    private(set) var periodError: String?
    private(set) var nextCursor: JourneyCursor?
    private var appliedSelection: (range: DateRange, start: Date, end: Date)?
    private var revision: Int?
    private var generation = 0
    private var pageTask: Task<Void, Never>?
    private var reportTask: Task<Void, Never>?
    private var reportGeneration = 0
    private let page: @MainActor (HistoryQuery, JourneyCursor?, Int) async throws -> JourneyPage
    private let buildReport: @MainActor (Range<Date>) throws -> Report
    private let asyncReport: (@MainActor (Range<Date>) async throws -> Report)?

    init(
        page: @escaping @MainActor (HistoryQuery, JourneyCursor?, Int) async throws -> JourneyPage,
        report: @escaping @MainActor (Range<Date>) throws -> Report,
        asyncReport: (@MainActor (Range<Date>) async throws -> Report)? = nil
    ) {
        self.page = page
        self.buildReport = report
        self.asyncReport = asyncReport
    }

    convenience init(store: UsageStore) {
        let service = HistoryQueryService(store: store)
        self.init(
            page: { query, cursor, limit in
                try await service.journeyPageAsync(for: query, before: cursor, limit: limit)
            }, report: { try store.report(in: $0) }, asyncReport: { try await service.report(in: $0) })
    }

    /// A refresh of the period already on screen keeps its report visible instead of blanking the pane.
    var keepsReportVisible: Bool { reportAnchor != nil && reportAnchor == periods?.current.lowerBound }

    func refresh(now: Date = .now, calendar: Calendar = .current) {
        do {
            periods = try range.resolve(
                now: now, calendar: calendar, customStart: customStart, customEnd: customEnd)
            appliedSelection = (range, customStart, customEnd)
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
        reportGeneration += 1
        reportTask?.cancel()
        if let asyncReport {
            let token = reportGeneration
            let compare = comparisonEnabled
            isReporting = true
            reportError = nil
            reportTask = Task { [weak self] in
                do {
                    let current = try await asyncReport(periods.current)
                    try Task.checkCancellation()
                    let previous: Report?
                    if compare, let interval = periods.previous {
                        previous = try await asyncReport(interval)
                    } else {
                        previous = nil
                    }
                    guard let self, self.reportGeneration == token, !Task.isCancelled else { return }
                    self.report = current
                    self.previousReport = previous
                    self.reportAnchor = periods.current.lowerBound
                    self.isReporting = false
                } catch is CancellationError {
                    return
                } catch {
                    guard let self, self.reportGeneration == token, !Task.isCancelled else { return }
                    self.reportError = "Report unavailable. History has been kept."
                    self.previousReport = nil
                    self.isReporting = false
                }
            }
            return
        }
        do {
            let current = try buildReport(periods.current)
            let previous = try comparisonEnabled ? periods.previous.map(buildReport) : nil
            report = current
            previousReport = previous
            reportAnchor = periods.current.lowerBound
            reportError = nil
        } catch {
            reportError = "Report unavailable. History has been kept."
            previousReport = nil
        }
    }

    func storeChanged(revision: Int, now: Date = .now) {
        guard self.revision != revision else { return }
        self.revision = revision
        refreshApplied(now: now, calendar: .current)
    }

    func dayChanged(now: Date, calendar: Calendar = .current) {
        guard let periods, !calendar.isDate(periods.asOf, inSameDayAs: now) else { return }
        refreshApplied(now: now, calendar: calendar)
    }

    private func refreshApplied(now: Date, calendar: Calendar) {
        guard let selection = appliedSelection else {
            refresh(now: now, calendar: calendar)
            return
        }
        do {
            periods = try selection.range.resolve(
                now: now, calendar: calendar, customStart: selection.start, customEnd: selection.end)
            updateReports()
            reloadJourney()
        } catch {
            stop()
            periodError = error.localizedDescription
        }
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

    func select(_ item: RankedItem, kind: HistoryKindFilter) {
        filter = HistoryFilter(text: "", kind: kind, nodeKey: item.key)
        selectedName = item.name
        selectionRevision += 1
        reloadJourney()
    }

    func clearFilters() {
        filter = HistoryFilter()
        selectedName = nil
        reloadJourney()
    }

    func stop() {
        generation += 1
        pageTask?.cancel()
        pageTask = nil
        reportGeneration += 1
        reportTask?.cancel()
        reportTask = nil
        isReporting = false
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
