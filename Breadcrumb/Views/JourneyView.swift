import AppKit
import SwiftUI

struct JourneyView: View {
    let rows: [JourneyRow]

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                "No journey yet",
                systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                description: Text("Switch between a few apps and your path will appear here.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { JourneyRowView(row: $0) }
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

    private var stemHeight: CGFloat {
        guard let dwell = row.dwell else { return 12 }
        let clipped = min(dwell, 30 * 60) / (30 * 60)
        return 12 + 36 * CGFloat(clipped.squareRoot())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(row.event.timestamp, format: .dateTime.hour().minute())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .trailing)
                .padding(.top, 8)
            VStack(spacing: 0) {
                marker.frame(width: 32, height: 32)
                Rectangle()
                    .fill(LinearGradient(colors: [.secondary.opacity(0.5), .secondary.opacity(0.1)], startPoint: .top, endPoint: .bottom))
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
        guard let dwell = row.dwell else { return kind }
        return "\(kind) · \(DurationFormat.short(dwell))"
    }

    @ViewBuilder private var marker: some View {
        if row.event.kind == .site {
            Circle().fill(.pink.opacity(0.6)).frame(width: 12, height: 12)
        } else if let icon = AppIcon.image(for: row.event.bundleID) {
            Image(nsImage: icon).resizable().accessibilityHidden(true)
        } else {
            Circle().strokeBorder(.secondary, lineWidth: 1).frame(width: 12, height: 12)
        }
    }
}

enum AppIcon {
    static func image(for bundleID: String?) -> NSImage? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
