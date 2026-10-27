import Combine
import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppRuntime.self) private var runtime
    @State private var range = DateRange.today
    @State private var now = Date.now
    private let refresh = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            if let tracker = runtime.tracker, let message = tracker.errorMessage {
                HStack {
                    Text(message)
                    Button("Retry") { tracker.retry() }
                }.padding(12)
            }
            if !runtime.preferences.hasConsent {
                PrivacyIntroduction()
            } else {
                HSplitView {
                    RangeSidebar(selection: $range)
                        .frame(minWidth: 140, idealWidth: 160, maxWidth: 220)
                    RangeContent(interval: range.interval(now: now), selection: range.rawValue)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .font(.system(.body, design: .monospaced))
        .background(PaperCanvas())
        .tint(BreadcrumbPalette.rose)
        .onReceive(refresh) {
            now = $0
            runtime.tracker?.refresh()
        }
        .alert(
            "Breadcrumb",
            isPresented: Binding(
                get: { runtime.messageBelongsToMainWindow && runtime.operationMessage != nil },
                set: { if !$0 { runtime.operationMessage = nil } }
            )
        ) {
            Button("OK") { runtime.operationMessage = nil }
        } message: {
            Text(runtime.operationMessage ?? "")
        }
    }
}

private struct RangeContent: View {
    @Environment(AppRuntime.self) private var runtime
    @Query private var recentEvents: [UsageEvent]
    let interval: Range<Date>
    let selection: String
    @State private var report = Report()
    @State private var reportError = false

    init(interval: Range<Date>, selection: String) {
        self.interval = interval
        self.selection = selection
        let start = interval.lowerBound
        let end = interval.upperBound
        var descriptor = FetchDescriptor<UsageEvent>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 200
        _recentEvents = Query(descriptor)
    }

    var body: some View {
        HSplitView {
            JourneyView(rows: ReportBuilder.journey(events: recentEvents.map(\.sample)))
                .frame(minWidth: 420, idealWidth: 620, maxHeight: .infinity)
            Group {
                if reportError {
                    VStack {
                        Text("Report unavailable. History has been kept.")
                        Button("Retry Report") { updateReport() }
                    }.padding()
                } else {
                    ReportView(report: report)
                }
            }.frame(minWidth: 280, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(
            id: ReportRefreshKey(
                selection: selection, start: interval.lowerBound,
                revision: runtime.store?.revision ?? 0, visibleIDs: recentEvents.map(\.id)
            )
        ) { updateReport() }
    }

    private func updateReport() {
        do {
            report = try runtime.store?.report(in: interval) ?? Report()
            reportError = false
        } catch {
            reportError = true
        }
    }
}

/// A clock tick alone does not invalidate aggregates; midnight, saves, and newly visible visits do.
private struct ReportRefreshKey: Equatable {
    let selection: String
    let start: Date
    let revision: Int
    let visibleIDs: [UUID]
}
