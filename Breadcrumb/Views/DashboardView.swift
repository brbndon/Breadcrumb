import SwiftUI

struct DashboardView: View {
    @Environment(AppRuntime.self) private var runtime
    @Bindable var model: DashboardModel
    let select: (ScreenTimeRow, HistoryKindFilter) -> Void
    @State private var showsAllApps = false
    @State private var showsAllSites = false
    @State private var contentWidth: CGFloat = 0

    private var summary: ScreenTimeSummary { model.summary }
    private let collapsedCount = 7

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if let error = model.error {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").accessibilityHidden(true)
                        Text(error)
                        Button("Retry") { model.refresh() }
                    }
                    .font(.system(.callout, design: .monospaced))
                }
                if summary.totalSeconds == 0 && !model.isLoading {
                    ContentUnavailableView(
                        "No recorded history", systemImage: "clock",
                        description: Text("Tracked visits will appear here.")
                    )
                    .padding(.vertical, 40)
                } else {
                    let slots = timeline
                    Group {
                        hero
                        chart(slots)
                        statistics(slots)
                        DottedDivider()
                        rankings
                    }
                    .opacity(model.isLoading && model.shown != nil ? 0.55 : 1)
                }
                footnotes
            }
            .frame(maxWidth: 980, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                contentWidth = $0
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: model.range) { model.refresh() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Kicker("Screen time")
                    Text(periodTitle).font(.system(.title3, design: .monospaced, weight: .semibold))
                }
                Spacer(minLength: 16)
                if model.isLoading {
                    ProgressView().controlSize(.small).accessibilityLabel("Loading screen time")
                }
                Picker("Period", selection: $model.range) {
                    ForEach(DateRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button("Refresh", systemImage: "arrow.clockwise") { model.refresh() }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut("r")
                    .help("Refresh screen time")
            }
            if model.range == .custom {
                HStack(spacing: 16) {
                    DatePicker("From", selection: $model.customStart, displayedComponents: .date)
                    DatePicker("Through", selection: $model.customEnd, displayedComponents: .date)
                    Button("Apply") { model.refresh() }
                }
                .fixedSize()
            }
        }
    }

    private var periodTitle: String {
        guard let periods = model.periods else { return model.range.rawValue }
        if model.range == .all { return "All recorded history" }
        let start = periods.current.lowerBound
        let end = max(start, periods.current.upperBound.addingTimeInterval(-0.001))
        let day = Date.FormatStyle.dateTime.weekday(.wide).month(.abbreviated).day()
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return start.formatted(day)
        }
        let short = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(start.formatted(short)) – \(end.formatted(short))"
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeroDuration(seconds: summary.totalSeconds)
            if let previous = model.previous, previous.totalSeconds > 0, summary.totalSeconds > 0,
                let phrase = comparisonPhrase
            {
                let change = summary.totalSeconds - previous.totalSeconds
                let rounded = abs(change) < 60
                Label {
                    Text(
                        rounded
                            ? "About the same as \(phrase)"
                            : "\(DurationFormat.short(abs(change))) \(change < 0 ? "less" : "more") than \(phrase)"
                    )
                } icon: {
                    Image(systemName: rounded ? "equal" : change < 0 ? "arrow.down.right" : "arrow.up.right")
                }
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.primary.opacity(0.05), in: .capsule)
            } else {
                Text("No preceding comparison available")
                    .font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var comparisonPhrase: String? {
        switch model.shown?.range {
        case .today: "yesterday at this time"
        case .yesterday: "the day before"
        case .week: "last week at this point"
        case .custom: "the preceding period"
        case .all, nil: nil
        }
    }

    private var comparisonName: String? {
        switch model.shown?.range {
        case .today: "Yesterday"
        case .yesterday: "Day before"
        case .week: "Last week"
        case .custom: "Previous"
        case .all, nil: nil
        }
    }

    // MARK: Chart

    private var timeline: [ScreenTimeSlot] {
        guard let shown = model.shown else { return [] }
        return ScreenTimeTimeline.slots(
            current: summary, previous: model.previous, periods: shown.periods, range: shown.range)
    }

    @ViewBuilder private func chart(_ slots: [ScreenTimeSlot]) -> some View {
        if !slots.isEmpty {
            let crumb = ScreenTimeTimeline.crumbValue(for: slots, unit: summary.bucketUnit)
            let comparison = slots.contains { ($0.previousSeconds ?? 0) > 0 } ? comparisonName : nil
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 18) {
                    Kicker(summary.bucketUnit == .hour ? "By hour" : "By day")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(BreadcrumbPalette.rose).frame(width: 7, height: 7)
                        Text(
                            "= \(crumb.truncatingRemainder(dividingBy: 3600) == 0 ? "\(Int(crumb / 3600))h" : DurationFormat.short(crumb))"
                        )
                    }
                    if let comparison {
                        HStack(spacing: 6) {
                            Capsule().fill(.primary.opacity(0.5)).frame(width: 12, height: 1.5)
                            Text(comparison)
                        }
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                CrumbChart(
                    slots: slots, unit: summary.bucketUnit, crumbValue: crumb, comparisonName: comparison)
            }
        }
    }

    // MARK: Statistics

    private func statistics(_ slots: [ScreenTimeSlot]) -> some View {
        let peak = slots.max { $0.seconds < $1.seconds }.flatMap { $0.seconds > 0 ? $0 : nil }
        let top = summary.apps.first
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 20, alignment: .topLeading)]) {
            StatTile(
                label: summary.bucketUnit == .hour ? "Busiest hour" : "Busiest day",
                value: peak.map {
                    summary.bucketUnit == .hour
                        ? $0.id.formatted(.dateTime.hour().minute())
                        : $0.id.formatted(.dateTime.weekday(.abbreviated).day())
                } ?? "—",
                detail: peak.map { DurationFormat.short($0.seconds) })
            StatTile(
                label: "Top app", value: top?.name ?? "—", app: top,
                detail: top.map { "\(share($0).formatted(.percent.precision(.fractionLength(0)))) of total" })
            StatTile(label: "Apps", value: "\(summary.apps.count)", detail: "with recorded time")
            StatTile(
                label: "Websites", value: summary.sites.isEmpty ? "—" : "\(summary.sites.count)",
                detail: summary.sites.isEmpty ? "none recorded" : "distinct hosts")
        }
    }

    // MARK: Rankings

    @ViewBuilder private var rankings: some View {
        if contentWidth >= 768 {
            HStack(alignment: .top, spacing: 48) {
                appsColumn.frame(maxWidth: .infinity)
                sitesColumn.frame(maxWidth: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: 36) {
                appsColumn
                sitesColumn
            }
        }
    }

    private var appsColumn: some View {
        RankingColumn(
            title: "Apps", rows: summary.apps, kind: .apps, total: summary.totalSeconds,
            collapsedCount: collapsedCount, showsAll: $showsAllApps, select: select)
    }

    private var sitesColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            RankingColumn(
                title: "Websites", rows: summary.sites, kind: .sites, total: summary.totalSeconds,
                collapsedCount: collapsedCount, showsAll: $showsAllSites, select: select)
            if runtime.preferences.enabledBrowserIDs.isEmpty {
                HStack(spacing: 8) {
                    Text("Enable Browser hosts in Settings to see websites.")
                    SettingsLink { Text("Open Settings") }
                }
                .font(.system(.caption, design: .monospaced))
            }
            FieldNote(symbol: "info.circle", text: "Zen records app-only time; its websites are unavailable.")
        }
    }

    // MARK: Footnotes

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: 10) {
            DottedDivider()
            if !runtime.preferences.pauseWhenIdle {
                FieldNote(
                    symbol: "moon.zzz", text: "Pause when idle is off. Away-from-desk time may be included.")
            }
            DisclosureGroup("About screen time") {
                Text(
                    "Screen time uses full recorded visit duration, including the newest ongoing visit through the last refresh. History’s Estimated time caps each visit at five minutes. Browser totals include their websites; website totals are also listed separately and must not be added to app totals."
                )
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(.caption, design: .monospaced))
        }
    }

    private func share(_ row: ScreenTimeRow) -> Double {
        summary.totalSeconds > 0 ? row.seconds / summary.totalSeconds : 0
    }
}

// MARK: - Pieces

private struct Kicker: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption2, design: .monospaced, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}

private struct FieldNote: View {
    let symbol: String
    let text: String
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
    }
}

/// The total set large, with unit letters receding so the numbers carry the line.
private struct HeroDuration: View {
    let seconds: TimeInterval

    var body: some View {
        let whole = Int(max(0, seconds).rounded())
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        Group {
            if whole < 60 {
                Text("\(number("\(whole)"))\(unit("s"))")
            } else if hours == 0 {
                Text("\(number("\(minutes)"))\(unit("m"))")
            } else {
                Text("\(number("\(hours)"))\(unit("h "))\(number("\(minutes)"))\(unit("m"))")
            }
        }
        .monospacedDigit()
        .accessibilityLabel(DurationFormat.short(seconds))
    }

    private func number(_ value: String) -> Text {
        Text(value).font(.system(size: 60, weight: .semibold, design: .monospaced))
    }

    private func unit(_ value: String) -> Text {
        Text(value).font(.system(size: 26, weight: .regular, design: .monospaced)).foregroundStyle(.secondary)
    }
}

private struct StatTile: View {
    let label: String
    let value: String
    var app: ScreenTimeRow?
    let detail: String?

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(BreadcrumbPalette.rose.opacity(0.7)).frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                Kicker(label)
                HStack(spacing: 8) {
                    if let app {
                        AppBadge(name: app.name, bundleID: app.bundleID).frame(width: 22, height: 22)
                    }
                    Text(value)
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                        .lineLimit(1).truncationMode(.tail)
                }
                Text(detail ?? " ").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct RankingColumn: View {
    let title: String
    let rows: [ScreenTimeRow]
    let kind: HistoryKindFilter
    let total: TimeInterval
    let collapsedCount: Int
    @Binding var showsAll: Bool
    let select: (ScreenTimeRow, HistoryKindFilter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Kicker(title)
                Spacer()
                if !rows.isEmpty {
                    Text("\(rows.count)").font(.system(.caption, design: .monospaced)).foregroundStyle(
                        .secondary
                    )
                    .accessibilityLabel("\(rows.count) \(title.lowercased())")
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            if rows.isEmpty {
                Text("Nothing recorded").font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            ForEach(showsAll ? rows : Array(rows.prefix(collapsedCount))) { row in
                RankRow(item: row, kind: kind, total: total, top: rows.first?.seconds ?? 0, select: select)
            }
            if rows.count > collapsedCount {
                Button(showsAll ? "Show fewer" : "Show all \(rows.count) \(title.lowercased())") {
                    showsAll.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundStyle(BreadcrumbPalette.rose)
                .padding(.horizontal, 8).padding(.top, 8)
            }
        }
    }
}

private struct RankRow: View {
    let item: ScreenTimeRow
    let kind: HistoryKindFilter
    let total: TimeInterval
    let top: TimeInterval
    let select: (ScreenTimeRow, HistoryKindFilter) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                select(item, kind)
            } label: {
                HStack(spacing: 12) {
                    marker.frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.name).lineLimit(1).truncationMode(.middle).layoutPriority(1)
                            DotLeader()
                            Text(DurationFormat.short(item.seconds)).monospacedDigit().layoutPriority(1)
                            Text(share.formatted(.percent.precision(.fractionLength(0))))
                                .foregroundStyle(.secondary).monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                        ShareBar(fraction: top > 0 ? item.seconds / top : 0)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 7)
                .background(.primary.opacity(hovering ? 0.05 : 0), in: .rect(cornerRadius: 6))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityLabel(
                "\(item.name), \(DurationFormat.short(item.seconds)), \(share.formatted(.percent.precision(.fractionLength(0)))) of screen time"
            )
            .accessibilityHint("Show matching History visits")
            if !item.sites.isEmpty {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0))
                        Text("\(item.sites.count) \(item.sites.count == 1 ? "website" : "websites")")
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.leading, 44).padding(.bottom, 4)
                .accessibilityLabel("\(expanded ? "Hide" : "Show") websites in \(item.name)")
                if expanded { trail }
            }
        }
    }

    private var share: Double { total > 0 ? item.seconds / total : 0 }

    /// Websites hang off their browser on a stem, like crumbs on the journey trail.
    private var trail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(item.sites.enumerated()), id: \.element.id) { index, site in
                Button {
                    select(site, .sites)
                } label: {
                    HStack(spacing: 12) {
                        ZStack(alignment: .top) {
                            Rectangle().fill(.secondary.opacity(0.35)).frame(width: 1)
                                .frame(height: index == item.sites.count - 1 ? 13 : 26)
                            Circle().fill(BreadcrumbPalette.rose).frame(width: 7, height: 7).padding(
                                .top, 9.5)
                        }
                        .frame(width: 24, height: 26, alignment: .top)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(site.name).lineLimit(1).truncationMode(.middle).layoutPriority(1)
                            DotLeader()
                            Text(DurationFormat.short(site.seconds)).monospacedDigit().layoutPriority(1)
                        }
                        .font(.system(.caption, design: .monospaced))
                        .padding(.trailing, 48)
                    }
                    .padding(.horizontal, 8)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(site.name) in \(item.name), \(DurationFormat.short(site.seconds))")
                .accessibilityHint("Show matching History visits")
            }
        }
        .padding(.bottom, 6)
        .transition(.opacity)
    }

    @ViewBuilder private var marker: some View {
        if kind == .sites {
            Circle().fill(BreadcrumbPalette.rose).frame(width: 10, height: 10)
        } else {
            AppBadge(name: item.name, bundleID: item.bundleID)
        }
    }
}

/// The app's own icon, or a lettered tile when the app is no longer installed.
private struct AppBadge: View {
    let name: String
    let bundleID: String?

    var body: some View {
        Group {
            if let icon = AppIcon.image(for: bundleID) {
                Image(nsImage: icon).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: geometry.size.width * 0.24)
                        .fill(BreadcrumbPalette.rose.opacity(0.14))
                        .strokeBorder(BreadcrumbPalette.rose.opacity(0.35), lineWidth: 0.5)
                        .overlay {
                            Text(name.first.map { String($0).uppercased() } ?? "?")
                                .font(
                                    .system(
                                        size: geometry.size.width * 0.5, weight: .semibold,
                                        design: .monospaced)
                                )
                                .foregroundStyle(BreadcrumbPalette.rose)
                        }
                        // Inset like a system icon so the tile lines up with real icons around it.
                        .padding(geometry.size.width * 0.08)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A row of round dots that sits on the text baseline between a name and its value.
private struct DotLeader: View {
    var body: some View {
        Canvas { context, size in
            var dots = Path()
            for x in stride(from: 1.0, through: size.width - 1, by: 5) {
                dots.addEllipse(in: CGRect(x: x - 0.75, y: size.height - 1.5, width: 1.5, height: 1.5))
            }
            context.fill(dots, with: .color(.secondary.opacity(0.45)))
        }
        .frame(minWidth: 12, maxWidth: .infinity)
        .frame(height: 2)
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
        .accessibilityHidden(true)
    }
}

private struct ShareBar: View {
    let fraction: Double

    var body: some View {
        Capsule().fill(.primary.opacity(0.06))
            .frame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule().fill(BreadcrumbPalette.rose)
                        .frame(width: max(3, geometry.size.width * min(1, fraction)))
                }
            }
            .accessibilityHidden(true)
    }
}
