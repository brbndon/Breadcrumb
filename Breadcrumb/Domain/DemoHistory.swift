import Foundation

/// Synthetic records for explicitly isolated demo runs; never reads existing history.
@MainActor
enum DemoHistory {
    static func populate(store: UsageStore, now: Date, calendar: Calendar = .current) throws {
        let today = calendar.startOfDay(for: now)
        var events: [EventSample] = []
        for offset in [-2, -1, 0] {
            if offset == 0 && now.timeIntervalSince(today) < 60 { continue }
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let span = offset == 0 ? max(1, min(14 * 3600, now.timeIntervalSince(today) - 60)) : 14 * 3600
            let begin = offset == 0 ? min(600, span / 2) : 600
            for index in 0..<320 {
                let node = (index / 2) % 10
                let site = index % 2 == 1
                let host =
                    node == 9
                    ? "a-very-long-example-host-name-for-layout-checks.example" : "site\(node).example"
                let name =
                    node < 2
                    ? "Same name"
                    : node == 9
                        ? "A very long synthetic application name for layout checks" : "Demo app \(node)"
                let stamp = day.addingTimeInterval(begin + (span - begin) * Double(index / 2) / 160)
                events.append(
                    EventSample(
                        id: UUID(), timestamp: stamp, kind: site ? .site : .app,
                        displayName: offset == 0 && index == 0 ? "Deep archive match" : site ? host : name,
                        bundleID: site || node == 2 ? "company.thebrowser.Browser" : "demo.bundle.\(node)",
                        host: site ? host : nil,
                        endedAt: index % 45 == 0 ? stamp.addingTimeInterval(3) : nil))
            }
        }
        events.append(
            EventSample(
                id: UUID(), timestamp: today.addingTimeInterval(-120), kind: .app,
                displayName: "Across midnight", bundleID: "demo.midnight", host: nil,
                endedAt: min(now, today.addingTimeInterval(120))))
        events.append(
            EventSample(
                id: UUID(), timestamp: today.addingTimeInterval(-7200), kind: .app,
                displayName: "Long recorded visit", bundleID: "demo.long", host: nil,
                endedAt: today.addingTimeInterval(-1800)))
        events.append(
            EventSample(
                id: UUID(), timestamp: today.addingTimeInterval(-14400), kind: .site,
                displayName: "youtube.com", bundleID: "company.thebrowser.Browser", host: "youtube.com",
                endedAt: today.addingTimeInterval(-9000)))
        try store.importSamples(events)
        try store.append(
            EventSample(
                id: UUID(), timestamp: now, kind: .app, displayName: "Ongoing demo visit",
                bundleID: "demo.ongoing", host: nil))
    }
}
