import AppKit
import SwiftUI

struct JourneyView: View {
    @Bindable var explorer: HistoryExplorer
    private var rows: [JourneyRow] { explorer.rows }

    var body: some View {
        VStack(spacing: 0) {
            if rows.isEmpty && !explorer.isLoading && explorer.journeyError == nil {
                ContentUnavailableView(
                    explorer.filter.isActive ? "No matching visits" : "No journey in this period",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    description: Text("Search applies to the complete selected period.")
                )
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index == 0
                            || !Calendar.current.isDate(
                                row.event.timestamp, inSameDayAs: rows[index - 1].event.timestamp)
                        {
                            Text(row.event.timestamp.formatted(date: .abbreviated, time: .omitted))
                                .font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding()
                        }
                        JourneyRowView(
                            row: row,
                            showTime: index == 0
                                || !Calendar.current.isDate(
                                    row.event.timestamp, equalTo: rows[index - 1].event.timestamp,
                                    toGranularity: .minute)
                        )
                    }
                    if explorer.isLoading {
                        ProgressView("Loading visits").padding()
                    } else if let message = explorer.journeyError {
                        Text(message).padding()
                        Button("Retry Journey") { explorer.retryJourney() }.padding()
                    } else if explorer.nextCursor != nil {
                        Button("Load older") { explorer.loadOlder() }
                            .accessibilityLabel("Load 100 older matching visits").padding()
                    } else if !rows.isEmpty {
                        Text("All matching visits loaded").font(.caption).foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .frame(maxWidth: 672)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct JourneyRowView: View {
    let row: JourneyRow
    let showTime: Bool

    private var stemHeight: CGFloat {
        guard let dwell = row.dwell else { return 12 }
        let clipped = min(dwell, 30 * 60) / (30 * 60)
        return 12 + 36 * CGFloat(clipped.squareRoot())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(showTime ? row.event.timestamp.formatted(.dateTime.hour().minute()) : "")
                .accessibilityLabel(row.event.timestamp.formatted(.dateTime.hour().minute()))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .trailing)
                .padding(.top, 8)
            VStack(spacing: 0) {
                marker.frame(width: 32, height: 32)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.secondary.opacity(0.5), .secondary.opacity(0.1)], startPoint: .top,
                            endPoint: .bottom)
                    )
                    .frame(width: 1, height: stemHeight)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.event.displayName).font(.system(.body, design: .monospaced))
                Text(subtitle).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            .padding(.top, 5)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let kind = row.event.kind == .app ? "APP" : "SITE"
        let duration = row.dwell.map(DurationFormat.short) ?? "Ongoing"
        let carried = row.isCarryIn ? " · Started before this period" : ""
        return "\(kind) · Recorded visit duration: \(duration)\(carried)"
    }

    @ViewBuilder private var marker: some View {
        if row.event.kind == .site {
            Circle().fill(BreadcrumbPalette.rose).frame(width: 12, height: 12)
        } else if let icon = AppIcon.image(for: row.event.bundleID) {
            Image(nsImage: icon).resizable().accessibilityHidden(true)
        } else {
            Circle().strokeBorder(.secondary, lineWidth: 1).frame(width: 12, height: 12)
        }
    }
}

@MainActor
enum AppIcon {
    /// Found icons only; a missing app is looked up again in case it is installed later.
    private static var cache: [String: NSImage] = [:]

    static func image(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let icon = cache[bundleID] { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}
