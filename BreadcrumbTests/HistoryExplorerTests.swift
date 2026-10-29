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
