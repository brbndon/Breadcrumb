import Combine
import SwiftData
import SwiftUI

struct RootView: View {
    @State private var range = DateRange.today
    @Query(sort: \UsageEvent.timestamp) private var allEvents: [UsageEvent]
    @State private var now = Date.now

    private let refresh = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    private var events: [EventSample] {
        let interval = range.interval(now: now)
        return allEvents.filter { interval.contains($0.timestamp) }.map(\.sample)
    }

    var body: some View {
        let events = events
        HSplitView {
            RangeSidebar(selection: $range)
                .frame(minWidth: 140, idealWidth: 160, maxWidth: 220)
            JourneyView(rows: Array(ReportBuilder.journey(events: events).prefix(200)))
                .frame(minWidth: 420, idealWidth: 620)
            ReportView(report: ReportBuilder.build(events: events))
                .frame(minWidth: 280)
        }
        .onReceive(refresh) { now = $0 }
    }
}
