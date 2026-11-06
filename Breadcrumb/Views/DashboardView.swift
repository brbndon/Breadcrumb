import AppKit
import Charts
import SwiftUI

struct DashboardView: View {
    @Environment(AppRuntime.self) private var runtime
    @Bindable var model: DashboardModel
    let select: (ScreenTimeRow, HistoryKindFilter) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Screen time").font(.title)
                    Spacer()
                    Picker("Period", selection: $model.range) {
                        ForEach(DateRange.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(width: 180)
                    Button("Refresh", systemImage: "arrow.clockwise") { model.refresh() }
                }
                if model.range == .custom {
                    HStack {
                        DatePicker("From", selection: $model.customStart, displayedComponents: .date)
                        DatePicker("Through", selection: $model.customEnd, displayedComponents: .date)
                        Button("Apply") { model.refresh() }
                    }
                }
                Text(DurationFormat.short(model.summary.totalSeconds)).font(.largeTitle).bold()
                if let previous = model.previous, previous.totalSeconds > 0, model.summary.totalSeconds > 0 {
                    let change = model.summary.totalSeconds - previous.totalSeconds
                    Text("\(change < 0 ? "−" : "+")\(DurationFormat.short(abs(change))) vs preceding period")
                } else {
                    Text("No preceding comparison available").foregroundStyle(.secondary)
                }
                if let periods = model.periods {
                    Text(
                        "\(periods.current.lowerBound.formatted()) – \(periods.current.upperBound.formatted())"
                    ).font(.caption)
                }
                if model.isLoading { ProgressView("Loading screen time") }
                if let error = model.error {
                    Text(error)
                    Button("Retry") { model.refresh() }
                }
                if model.summary.totalSeconds == 0 && !model.isLoading {
                    ContentUnavailableView(
                        "No recorded history", systemImage: "clock",
                        description: Text("Tracked visits will appear here."))
                }
                Chart(model.summary.buckets) { bucket in
                    BarMark(
                        x: .value("Time", bucket.id, unit: model.summary.bucketUnit),
                        y: .value("Minutes", bucket.seconds / 60)
                    )
                    .foregroundStyle(BreadcrumbPalette.rose)
                }
                .frame(height: 180)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "Activity chart. \(DurationFormat.short(model.summary.totalSeconds)) across \(model.summary.buckets.count) active time buckets."
                )
                DottedDivider()
                Text("Apps").font(.headline)
                ForEach(model.summary.apps) { app in
                    if app.sites.isEmpty {
                        row(app, kind: .apps)
                    } else {
                        DisclosureGroup {
                            ForEach(app.sites) { row($0, kind: .sites) }
                        } label: {
                            row(app, kind: .apps)
                        }
                    }
                }
                DottedDivider()
                Text("Websites").font(.headline)
                Text("Zen records app-only time; its websites are unavailable.").font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(model.summary.sites) { row($0, kind: .sites) }
                if runtime.preferences.enabledBrowserIDs.isEmpty {
                    Text("Enable Browser hosts in Settings to see websites.")
                    SettingsLink { Text("Open Settings") }
                }
                if !runtime.preferences.pauseWhenIdle {
                    Text("Pause when idle is off. Away-from-desk time may be included.").foregroundStyle(
                        .secondary)
                }
                DisclosureGroup("About screen time") {
                    Text(
                        "Screen time uses full recorded visit duration, including the newest ongoing visit through the last refresh. History’s Estimated time caps each visit at five minutes. Browser totals include their websites; website totals are also listed separately and must not be added to app totals."
                    )
                }
            }.padding(24)
        }
        .onChange(of: model.range) { model.refresh() }
    }

    private func row(_ item: ScreenTimeRow, kind: HistoryKindFilter) -> some View {
        Button {
            select(item, kind)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if kind == .apps, let id = item.bundleID,
                        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
                    {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(
                            width: 22, height: 22)
                    } else {
                        Image(systemName: kind == .sites ? "globe" : "app").frame(width: 22)
                    }
                    Text(item.name).lineLimit(1)
                    Spacer()
                    Text(DurationFormat.short(item.seconds))
                    Text(
                        (model.summary.totalSeconds > 0 ? item.seconds / model.summary.totalSeconds : 0)
                            .formatted(.percent.precision(.fractionLength(0)))
                    )
                    .frame(width: 55, alignment: .trailing)
                }
                ProgressView(value: item.seconds, total: max(item.seconds, model.summary.totalSeconds, 1))
                    .accessibilityHidden(true)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityHint("Show matching History visits")
    }
}
