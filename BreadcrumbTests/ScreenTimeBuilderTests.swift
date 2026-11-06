import Foundation
import Testing

@testable import Breadcrumb

struct ScreenTimeBuilderTests {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    func event(_ offset: Double, end: Double? = nil, host: String? = nil, bundle: String = "browser")
        -> EventSample
    {
        EventSample(
            id: UUID(), timestamp: base.addingTimeInterval(offset), kind: host == nil ? .app : .site,
            displayName: host ?? "Browser", bundleID: bundle, host: host,
            endedAt: end.map { base.addingTimeInterval($0) })
    }
    func build(_ events: [EventSample], start: Double = 0, end: Double = 10000, asOf: Double = 10000)
        -> ScreenTimeSummary
    {
        var accumulator = ScreenTimeBuilder.Accumulator(
            interval: base.addingTimeInterval(start)..<base.addingTimeInterval(end),
            asOf: base.addingTimeInterval(asOf))
        for event in events { accumulator.append(event) }
        return accumulator.summary()
    }
    @Test func clippingCarryInCarryOutAndUncappedDuration() {
        let result = build([event(-100), event(7200)], start: 0, end: 3600)
        #expect(result.totalSeconds == 3600)
        #expect(result.apps.first?.seconds == 3600)
    }
    @Test func closedSegmentsNeverBridgeAndOngoingUsesCutoff() {
        let result = build([event(0, end: 60), event(600)], asOf: 1200)
        #expect(result.totalSeconds == 660)
        #expect(build([event(0)], asOf: 0).totalSeconds == 0)
    }
    @Test func browserRollupAndNormalizedSitesAcrossBrowsers() {
        let result = build(
            [
                event(0), event(100, host: "www.example.com"),
                event(200, host: "m.example.com", bundle: "other"),
            ], asOf: 300)
        #expect(result.totalSeconds == 300)
        #expect(result.sites.count == 1)
        #expect(result.sites.first?.seconds == 200)
        #expect(result.apps.first?.seconds == 200)
        #expect(result.apps.first?.sites.first?.seconds == 100)
    }
    @Test func calendarBucketsSplitMidnightAndDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        let end = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        var accumulator = ScreenTimeBuilder.Accumulator(interval: start..<end, asOf: end, calendar: calendar)
        accumulator.append(
            EventSample(
                id: UUID(), timestamp: start, kind: .app, displayName: "App", bundleID: nil, host: nil))
        let result = accumulator.summary()
        #expect(result.totalSeconds == 25 * 3600)
        #expect(result.buckets.count == 25)
        let next = try #require(calendar.date(byAdding: .day, value: 1, to: end))
        var daily = ScreenTimeBuilder.Accumulator(interval: start..<next, asOf: next, calendar: calendar)
        daily.append(
            EventSample(
                id: UUID(), timestamp: start, kind: .app, displayName: "App", bundleID: nil, host: nil))
        #expect(daily.summary().buckets.count == 2)
        var hourly = ScreenTimeBuilder.Accumulator(
            interval: start..<start.addingTimeInterval(4 * 3600), asOf: end, calendar: calendar)
        hourly.append(
            EventSample(
                id: UUID(), timestamp: start, kind: .app, displayName: "App", bundleID: nil, host: nil))
        #expect(hourly.summary().buckets.count == 4)
    }
    @Test @MainActor func multiBatchQueryMatchesPureBuilder() async throws {
        let store = try UsageStore.open(inMemory: true)
        let events = (0..<1205).map { event(Double($0) * 2, end: Double($0) * 2 + 1) }
        try store.importSamples(events)
        let summary = try await HistoryQueryService(store: store).screenTime(
            in: base..<base.addingTimeInterval(10000), asOf: base.addingTimeInterval(10000))
        #expect(summary == build(events))
    }

    @Test func hostNormalizationKeepsTwoLabels() {
        #expect(ScreenTimeBuilder.normalizedHost("WWW.Example.com") == "example.com")
        #expect(ScreenTimeBuilder.normalizedHost("m.www.example.com") == "example.com")
        #expect(ScreenTimeBuilder.normalizedHost("m.me") == "m.me")
        #expect(ScreenTimeBuilder.normalizedHost("www.com") == "www.com")
    }
    @Test @MainActor func queryUsesStoredNeighborsForCarryInAndCarryOut() async throws {
        let store = try UsageStore.open(inMemory: true)
        let events = [event(0), event(1500, host: "a.example"), event(3000, end: 3100)]
        try store.importSamples(events)
        let interval = base.addingTimeInterval(1000)..<base.addingTimeInterval(2000)
        let asOf = base.addingTimeInterval(10000)
        let summary = try await HistoryQueryService(store: store).screenTime(in: interval, asOf: asOf)
        #expect(summary == build(events, start: 1000, end: 2000, asOf: 10000))
        #expect(summary.totalSeconds == 1000)
        #expect(summary.sites.first?.seconds == 500)
    }
    @Test @MainActor func equalTimestampsAcrossABatchBoundaryMatchTheBuilder() async throws {
        let store = try UsageStore.open(inMemory: true)
        var events = (0..<499).map { event(Double($0) * 2, end: Double($0) * 2 + 1) }
        events += (0..<4).map { event(998, host: "tie\($0).example") }
        events += (0..<20).map { event(1000 + Double($0) * 2, end: 1000 + Double($0) * 2 + 1) }
        try store.importSamples(events)
        let ordered = events.sorted(by: ReportBuilder.chronological)
        let summary = try await HistoryQueryService(store: store).screenTime(
            in: base..<base.addingTimeInterval(10000), asOf: base.addingTimeInterval(10000))
        #expect(summary == build(ordered))
    }
    @Test @MainActor func cancellationAndRevisionChangesStopTheQuery() async throws {
        let store = try UsageStore.open(inMemory: true)
        try store.importSamples((0..<3000).map { event(Double($0) * 2, end: Double($0) * 2 + 1) })
        let service = HistoryQueryService(store: store)
        let range = base..<base.addingTimeInterval(10000)
        let cancelled = Task { try await service.screenTime(in: range, asOf: range.upperBound) }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        let superseded = Task { try await service.screenTime(in: range, asOf: range.upperBound) }
        await Task.yield()
        try store.importSamples([event(9000, end: 9001)])
        await #expect(throws: CancellationError.self) { try await superseded.value }
    }
}
