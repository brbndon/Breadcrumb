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
