import Foundation
import Testing

@testable import Breadcrumb

@MainActor
private final class PageGate {
    var pending: [CheckedContinuation<JourneyPage, any Error>] = []
    func read() async throws -> JourneyPage {
        try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func finish(_ index: Int, rows: [JourneyRow]) {
        pending[index].resume(returning: JourneyPage(rows: rows, nextCursor: nil))
    }
}

@MainActor
struct HistoryExplorerTests {
    private func row(_ name: String) -> JourneyRow {
        JourneyRow(
            event: EventSample(
                id: UUID(), timestamp: .now, kind: .app, displayName: name, bundleID: name, host: nil),
            dwell: nil)
    }
    private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() { await Task.yield() }
    }
    @Test func oldSearchCannotReplaceNewQuery() async {
        let gate = PageGate()
        let explorer = HistoryExplorer(page: { _, _, _ in try await gate.read() }, report: { _ in Report() })
        explorer.refresh(now: .now)
        await waitFor { gate.pending.count == 1 }
        explorer.filter.text = "new"
        explorer.reloadJourney()
        await waitFor { gate.pending.count == 2 }
        gate.finish(1, rows: [row("New")])
        await waitFor { explorer.rows.count == 1 }
        gate.finish(0, rows: [row("Old")])
        await Task.yield()
        #expect(explorer.rows.first?.event.displayName == "New")
        explorer.stop()
    }
    @Test func revisionInvalidatesOldPageAndReports() async {
        let gate = PageGate()
        var reports = 0
        let explorer = HistoryExplorer(
            page: { _, _, _ in try await gate.read() },
            report: { _ in
                reports += 1
                return Report()
            })
        let now = Date.now
        explorer.refresh(now: now)
        await waitFor { gate.pending.count == 1 }
        explorer.storeChanged(revision: 1, now: now)
        await waitFor { gate.pending.count == 2 }
        gate.finish(1, rows: [row("New store")])
        await waitFor { explorer.rows.count == 1 }
        gate.finish(0, rows: [row("Old store")])
        await Task.yield()
        #expect(explorer.rows.first?.event.displayName == "New store")
        #expect(reports == 2)
        explorer.stop()
    }
}

extension HistoryExplorerTests {
    @Test func drillDownSelectsExactNodeAndDoesNotRebuildWholePeriodReports() async {
        var reports = 0
        let explorer = HistoryExplorer(
            page: { _, _, _ in JourneyPage(rows: [], nextCursor: nil) },
            report: { _ in
                reports += 1
                return Report()
            })
        explorer.refresh()
        let period = explorer.periods
        explorer.filter = HistoryFilter(text: "conflict", kind: .sites)
        explorer.select(
            RankedItem(key: "app:exact.a", name: "Same", bundleID: "exact.a", visits: 1, total: 60),
            kind: .apps)
        #expect(explorer.filter.text.isEmpty)
        #expect(explorer.filter.kind == .apps)
        #expect(explorer.filter.nodeKey == "app:exact.a")
        #expect(explorer.periods == period)
        #expect(reports == 1)
        explorer.clearFilters()
        #expect(!explorer.filter.isActive)
        explorer.stop()
    }
}
