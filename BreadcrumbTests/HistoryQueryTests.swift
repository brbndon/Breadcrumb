import Foundation
import SwiftData
import Testing

@testable import Breadcrumb

@MainActor
struct HistoryQueryTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private func event(_ index: Int, time: Double? = nil, name: String? = nil, kind: EventKind = .app)
        -> EventSample
    {
        EventSample(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
            timestamp: base.addingTimeInterval(time ?? Double(index)), kind: kind,
            displayName: name ?? "App \(index)", bundleID: "bundle.\(index)",
            host: kind == .site ? "host\(index).example" : nil)
    }
    private func query(_ filter: HistoryFilter = HistoryFilter()) -> HistoryQuery {
        HistoryQuery(interval: base..<base.addingTimeInterval(1000), filter: filter)
    }
    @Test func pagesAll305EventsAndSearchesPastOldLimit() throws {
        let store = try UsageStore.open(inMemory: true)
        try store.importSamples((0..<305).map { event($0) })
        let service = HistoryQueryService(store: store)
        var ids: [UUID] = []
        var cursor: JourneyCursor?
        repeat {
            let page = try service.journeyPage(for: query(), before: cursor, limit: 100)
            #expect(page.rows.count <= 100)
            ids += page.rows.map(\.id)
            cursor = page.nextCursor
        } while cursor != nil
        #expect(ids.count == 305)
        #expect(Set(ids).count == 305)
        let page = try service.journeyPage(
            for: query(HistoryFilter(text: "bundle.0")), before: nil, limit: 100)
        #expect(page.rows.map(\.event.bundleID) == ["bundle.0"])
        #expect(page.nextCursor == nil)
    }
    @Test func tiesAreUUIDDescendingAcrossLargeBucket() throws {
        let store = try UsageStore.open(inMemory: true)
        let events = (0..<1205).map { event($0, time: 10) }
        try store.importSamples(events.reversed())
        let service = HistoryQueryService(store: store)
        var ids: [UUID] = []
        var cursor: JourneyCursor?
        repeat {
            let page = try service.journeyPage(for: query(), before: cursor, limit: 100)
            ids += page.rows.map(\.id)
            cursor = page.nextCursor
        } while cursor != nil
        #expect(ids == events.reversed().map(\.id))
    }
    @Test func searchAndKindAndExactNodeAreCombinedBeforeLimit() throws {
        let store = try UsageStore.open(inMemory: true)
        try store.importSamples([event(0, name: "ALPHA"), event(1, name: "Alpha", kind: .site), event(2)])
        let service = HistoryQueryService(store: store)
        let filter = HistoryFilter(text: "aLpHa", kind: .sites, nodeKey: "site:host1.example")
        #expect(
            try service.journeyPage(for: query(filter), before: nil, limit: 1).rows.map(\.event.kind) == [
                .site
            ])
        #expect(
            try service.journeyPage(for: query(HistoryFilter(text: "HOST1")), before: nil, limit: 10).rows
                .count == 1)
        #expect(
            try service.journeyPage(for: query(HistoryFilter(text: "   ")), before: nil, limit: 10).rows.count
                == 3)
        #expect(
            try service.journeyPage(for: query(HistoryFilter(text: "missing")), before: nil, limit: 10).rows
                .isEmpty)
    }
    @Test func filteredDwellUsesOriginalSuccessorIncludingAtPageBoundary() throws {
        let store = try UsageStore.open(inMemory: true)
        let a = event(0, time: 0, name: "A")
        try store.append(a)
        try store.append(event(1, time: 60, name: "B"))
        try store.append(event(2, time: 180, name: "A"))
        let service = HistoryQueryService(store: store)
        let q = query(HistoryFilter(text: "A", kind: .apps))
        let first = try service.journeyPage(for: q, before: nil, limit: 1)
        #expect(first.rows.first?.dwell == nil)
        let second = try service.journeyPage(for: q, before: first.nextCursor, limit: 1)
        #expect(second.rows.first?.id == a.id)
        #expect(second.rows.first?.dwell == 60)
        #expect(second.nextCursor == nil)
    }
    @Test func includesOnlyOverlappingCarryInAndKeepsOriginalTimestamp() throws {
        let store = try UsageStore.open(inMemory: true)
        let a = event(0, time: -60)
        try store.append(a)
        try store.append(event(1, time: 60))
        let service = HistoryQueryService(store: store)
        let page = try service.journeyPage(for: query(), before: nil, limit: 100)
        #expect(page.rows.last?.id == a.id)
        #expect(page.rows.last?.isCarryIn == true)
        #expect(page.rows.last?.dwell == 120)
        try store.close(id: a.id, at: base)
        #expect(try service.journeyPage(for: query(), before: nil, limit: 100).rows.count == 1)
    }
}

extension HistoryQueryTests {
    @Test func syntheticDemoHasCompleteRankingsBoundariesAndOngoingVisit() throws {
        let store = try UsageStore.open(inMemory: true)
        let now = base.addingTimeInterval(12 * 3600)
        try DemoHistory.populate(store: store, now: now)
        let service = HistoryQueryService(store: store)
        let interval = Calendar.current.startOfDay(for: now)..<now.addingTimeInterval(1)
        let page = try service.journeyPage(
            for: HistoryQuery(interval: interval, filter: HistoryFilter()), before: nil, limit: 100)
        #expect(page.rows.count == 100)
        #expect(page.nextCursor != nil)
        #expect(page.rows.first?.dwell == nil)
        let report = try store.report(in: Date(timeIntervalSince1970: 0)..<now.addingTimeInterval(1))
        #expect(report.topApps.count >= 8)
        #expect(report.topSites.count >= 8)
        #expect(report.topApps.filter { $0.name == "Same name" }.count == 2)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["BREADCRUMB_LARGE_TEST"] == "1"))
    func largeSyntheticStoreKeepsPagesBoundedAndComparisonCorrect() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Breadcrumb-Large-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try UsageStore.open(in: directory)
        let samples = (0..<250_000).map { index in
            EventSample(
                id: event(index).id, timestamp: base.addingTimeInterval(Double(index)), kind: .app,
                displayName: "App \(index % 20)", bundleID: "large.bundle.\(index % 20)", host: nil)
        }
        let clock = ContinuousClock()
        let inserted = clock.now
        for start in stride(from: 0, to: samples.count, by: 1000) {
            let context = ModelContext(store.container)
            context.autosaveEnabled = false
            for sample in samples[start..<min(start + 1000, samples.count)] {
                let event = UsageEvent(
                    id: sample.id, timestamp: sample.timestamp, kind: sample.kind,
                    displayName: sample.displayName, bundleID: sample.bundleID, host: nil)
                if sample.id == samples.last?.id { event.endedAt = sample.timestamp }
                context.insert(event)
            }
            try context.save()
        }
        print("Large fixture insertion: \(inserted.duration(to: clock.now))")
        let q = HistoryQuery(interval: base..<base.addingTimeInterval(250_000), filter: HistoryFilter())
        let service = HistoryQueryService(store: store)
        let start = clock.now
        let first = try await service.journeyPageAsync(for: q, before: nil, limit: 100)
        let second = try await service.journeyPageAsync(for: q, before: first.nextCursor, limit: 100)
        #expect(first.rows.count == 100 && second.rows.count == 100)
        #expect(Set(first.rows.map(\.id)).isDisjoint(with: second.rows.map(\.id)))
        print("Large fixture two pages: \(start.duration(to: clock.now))")
        let aggregates = clock.now
        let earlier = try await service.report(in: base..<base.addingTimeInterval(125_000))
        let later = try await service.report(
            in: base.addingTimeInterval(125_000)..<base.addingTimeInterval(250_000))
        #expect(earlier.topApps.reduce(0) { $0 + $1.visits } == 125_000)
        #expect(later.topApps.reduce(0) { $0 + $1.visits } == 125_000)
        print("Large fixture comparison: \(aggregates.duration(to: clock.now))")
    }
}

extension HistoryQueryTests {
    @Test func demoAtMidnightDoesNotCreateFutureRecords() throws {
        let store = try UsageStore.open(inMemory: true)
        let midnight = Calendar.current.startOfDay(for: base)
        try DemoHistory.populate(store: store, now: midnight)
        let end = midnight.addingTimeInterval(1)
        let descriptor = FetchDescriptor<UsageEvent>(
            predicate: #Predicate { $0.timestamp > midnight && $0.timestamp < end })
        #expect(try store.context.fetchCount(descriptor) == 0)
    }
}

extension HistoryQueryTests {
    @Test func asyncScansYieldAndMatchSynchronousReports() async throws {
        let store = try UsageStore.open(inMemory: true)
        try store.importSamples((0..<2005).map { event($0) })
        let service = HistoryQueryService(store: store)
        let interval = base..<base.addingTimeInterval(3000)
        var yielded = false
        let marker = Task { @MainActor in yielded = true }
        let page = try await service.journeyPageAsync(
            for: HistoryQuery(interval: interval, filter: HistoryFilter(text: "not recorded")), before: nil,
            limit: 100)
        #expect(page.rows.isEmpty)
        #expect(yielded)
        await marker.value
        let expected = try store.report(in: interval)
        yielded = false
        let reportMarker = Task { @MainActor in yielded = true }
        let report = try await service.report(in: interval)
        #expect(yielded)
        #expect(report == expected)
        await reportMarker.value
    }
}

extension HistoryQueryTests {
    @Test func emptyIntervalDoesNotShowCarryIn() throws {
        let store = try UsageStore.open(inMemory: true)
        try store.append(event(0, time: -60))
        try store.append(event(1, time: 60))
        let page = try HistoryQueryService(store: store).journeyPage(
            for: HistoryQuery(interval: base..<base, filter: HistoryFilter()), before: nil, limit: 100)
        #expect(page.rows.isEmpty)
    }
}
