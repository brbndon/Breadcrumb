import Foundation
import Testing

@testable import Breadcrumb

@MainActor
struct DashboardModelTests {
    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }
    @Test func periodRevisionRolloverAndInvalidEdits() async {
        var calls = 0
        let model = DashboardModel { _, _, _ in
            calls += 1
            return ScreenTimeSummary(totalSeconds: Double(calls))
        }
        let now = Date.now
        model.storeChanged(revision: 1, now: now)
        await settle { !model.isLoading }
        #expect(calls == 2)
        model.storeChanged(revision: 1, now: now)
        model.dayChanged(now: now)
        #expect(calls == 2)
        model.dayChanged(now: Calendar.current.date(byAdding: .day, value: 1, to: now)!)
        await settle { !model.isLoading }
        #expect(calls == 4)
        let period = model.periods
        model.range = .custom
        model.customStart = now.addingTimeInterval(86400)
        model.customEnd = now
        model.refresh(now: now)
        #expect(model.periods == period)
        #expect(model.error != nil)
        #expect(model.shown?.range == .today)
        model.range = .all
        model.refresh(now: now)
        await settle { !model.isLoading }
        #expect(model.previous == nil)
        #expect(model.shown?.range == .all)
        #expect(model.shown?.periods == model.periods)
        model.stop()
    }
    @Test func stoppedOrSupersededResultsCannotPublish() async {
        var pending: [CheckedContinuation<ScreenTimeSummary, any Error>] = []
        let model = DashboardModel { _, _, _ in
            try await withCheckedThrowingContinuation { pending.append($0) }
        }
        model.range = .all
        model.refresh()
        await settle { pending.count == 1 }
        model.refresh()
        await settle { pending.count == 2 }
        pending[1].resume(returning: ScreenTimeSummary(totalSeconds: 20))
        await settle { !model.isLoading }
        pending[0].resume(returning: ScreenTimeSummary(totalSeconds: 10))
        await Task.yield()
        #expect(model.summary.totalSeconds == 20)
        model.refresh()
        await settle { pending.count == 3 }
        model.stop()
        pending[2].resume(returning: ScreenTimeSummary(totalSeconds: 30))
        await Task.yield()
        #expect(model.summary.totalSeconds == 20)
    }

    @Test func rowSelectionOpensHistoryForTheAppliedPeriodWithRollupSemantics() async throws {
        let calendar = Calendar.current
        let yesterday = try #require(
            calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: .now)))
        func visit(_ hours: Double, host: String?, bundle: String) -> EventSample {
            EventSample(
                id: UUID(), timestamp: yesterday.addingTimeInterval(hours * 3600),
                kind: host == nil ? .app : .site, displayName: host ?? "Browser", bundleID: bundle,
                host: host, endedAt: yesterday.addingTimeInterval(hours * 3600 + 600))
        }
        let store = try UsageStore.open(inMemory: true)
        try store.importSamples([
            visit(1, host: nil, bundle: "browser"), visit(2, host: "www.example.com", bundle: "browser"),
            visit(3, host: "m.example.com", bundle: "other"), visit(4, host: nil, bundle: "unrelated"),
        ])
        let model = DashboardModel(store: store)
        model.range = .yesterday
        model.refresh()
        await settle { !model.isLoading }
        #expect(model.summary.totalSeconds == 2400)
        let explorer = HistoryExplorer(store: store)
        model.configureHistory(explorer)
        #expect(explorer.range == .yesterday)
        explorer.select(
            RankedItem(key: "app:browser", name: "Browser", bundleID: "browser", visits: 0, total: 0),
            kind: .apps, screenTime: true)
        await settle { !explorer.isLoading && explorer.rows.count == 2 }
        #expect(Set(explorer.rows.map(\.event.displayName)) == ["Browser", "www.example.com"])
        explorer.select(
            RankedItem(key: "site:example.com", name: "example.com", bundleID: nil, visits: 0, total: 0),
            kind: .sites, screenTime: true)
        await settle { !explorer.isLoading && explorer.rows.count == 2 }
        #expect(Set(explorer.rows.map(\.event.displayName)) == ["www.example.com", "m.example.com"])
        explorer.select(
            RankedItem(key: "site:example.com", name: "example.com", bundleID: nil, visits: 0, total: 0),
            kind: .sites)
        await settle { !explorer.isLoading }
        #expect(explorer.rows.isEmpty)
        model.stop()
        explorer.stop()
    }
}
