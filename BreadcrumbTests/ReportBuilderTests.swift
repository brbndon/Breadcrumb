import Foundation
import Testing

@testable import Breadcrumb

struct ReportBuilderTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ name: String, at seconds: TimeInterval) -> EventSample {
        EventSample(
            id: UUID(), timestamp: base.addingTimeInterval(seconds), kind: .app, displayName: name,
            bundleID: "id.\(name)", host: nil)
    }

    @Test func emptyEventsGiveEmptyReport() {
        #expect(ReportBuilder.build(events: []) == Report())
    }

    @Test func countsSwitchesAppsAndTransitions() {
        let report = ReportBuilder.build(events: [
            event("A", at: 0), event("B", at: 60), event("A", at: 120), event("B", at: 180),
        ])
        #expect(report.switches == 3)
        #expect(report.apps == 2)
        #expect(report.transitions.first?.count == 2)
        #expect(report.transitions.first?.from == "A")
    }

    @Test func activeTimeCapsEachDwellAtFiveMinutes() {
        let report = ReportBuilder.build(events: [
            event("A", at: 0), event("B", at: 3600), event("A", at: 3660),
        ])
        // A: capped 300s, B: 60s, last: 0 → 360s = 6m
        #expect(report.activeMinutes == 6)
    }

    @Test func journeyIsNewestFirstAndNewestHasNoDwell() {
        let rows = ReportBuilder.journey(events: [event("A", at: 0), event("B", at: 90)])
        #expect(rows.map(\.event.displayName) == ["B", "A"])
        #expect(rows[0].dwell == nil)
        #expect(rows[1].dwell == 90)
    }

    @Test func invalidDurationDoesNotCrashFormatting() {
        #expect(DurationFormat.short(.infinity) == "—")
        #expect(DurationFormat.short(.nan) == "—")
        #expect(DurationFormat.short(.greatestFiniteMagnitude) == "—")
        #expect(DurationFormat.short(-10) == "0s")
    }

    @Test func identicallyNamedAppsHaveDistinctTransitionIDs() {
        let otherB = EventSample(
            id: UUID(), timestamp: base.addingTimeInterval(180),
            kind: .app, displayName: "B", bundleID: "other.B", host: nil)
        let report = ReportBuilder.build(events: [
            event("A", at: 0), event("B", at: 60), event("A", at: 120), otherB,
        ])
        #expect(Set(report.transitions.map(\.id)).count == report.transitions.count)
    }
}

extension ReportBuilderTests {
    @Test func capIsNotRenewedAtRangeBoundary() {
        let events = [event("A", at: 0), event("B", at: 3600)]
        let interval = base.addingTimeInterval(600)..<base.addingTimeInterval(1200)
        let report = ReportBuilder.build(events: events, in: interval)
        #expect(report.activeMinutes == 0)
        #expect(report.topApps.first?.visits == 1)
    }

    @Test func successorOutsideIntervalResolvesDwellWithoutCountingDestination() {
        let report = ReportBuilder.build(
            events: [event("A", at: 0), event("B", at: 60)], in: base..<base.addingTimeInterval(60))
        #expect(report.apps == 1)
        #expect(report.switches == 0)
        #expect(report.activeMinutes == 1)
    }

    @Test func explicitClosureAndCarryInAreClippedOnce() {
        var a = event("A", at: 0)
        a.endedAt = base.addingTimeInterval(120)
        let events = [a, event("B", at: 600)]
        let report = ReportBuilder.build(
            events: events, in: base.addingTimeInterval(60)..<base.addingTimeInterval(700))
        #expect(report.activeMinutes == 1)
        #expect(report.switches == 0)
        #expect(report.apps == 2)
    }

    @Test func zeroNegativeAndUnknownVisitsInsideRangeRemainVisits() {
        var a = event("A", at: 0)
        a.endedAt = base.addingTimeInterval(-10)
        let report = ReportBuilder.build(
            events: [a, event("B", at: 0), event("C", at: 1)], in: base..<base.addingTimeInterval(2))
        #expect(report.apps == 3)
        #expect(report.activeMinutes == 0)
    }
}

extension ReportBuilderTests {
    @Test func rankingsRetainMoreThanSixAppsAndSites() {
        let apps = (0..<9).map { event("App \($0)", at: Double($0) * 60) }
        let sites = (0..<9).map { index in
            EventSample(
                id: UUID(), timestamp: base.addingTimeInterval(600 + Double(index) * 60), kind: .site,
                displayName: "site\(index).example", bundleID: "browser", host: "site\(index).example")
        }
        let report = ReportBuilder.build(events: apps + sites)
        #expect(report.topApps.count == 9)
        #expect(report.topSites.count == 9)
    }
    @Test func rankingSortsUseDeterministicNameAndNodeTies() {
        let items = [
            RankedItem(key: "app:b", name: "Same", bundleID: "b", visits: 2, total: 10),
            RankedItem(key: "app:a", name: "Same", bundleID: "a", visits: 2, total: 10),
            RankedItem(key: "app:c", name: "Other", bundleID: "c", visits: 1, total: 90),
        ]
        #expect(ReportBuilder.rankedItems(items, by: .visits).map(\.key) == ["app:a", "app:b", "app:c"])
        #expect(
            ReportBuilder.rankedItems(items, by: .estimatedTime).map(\.key) == ["app:c", "app:a", "app:b"])
    }
}
