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
