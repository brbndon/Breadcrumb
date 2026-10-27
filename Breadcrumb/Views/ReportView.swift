import SwiftUI

struct ReportView: View {
    let report: Report

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    stat("Switches", "\(report.switches)")
                    stat("Apps", "\(report.apps)")
                    stat("Active", "\(report.activeMinutes)m")
                }
                section("Top apps", report.topApps, showIcon: true)
                section("Top sites", report.topSites, showIcon: false)
                transitions
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .monospaced, weight: .bold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func section(_ title: String, _ items: [RankedItem], showIcon: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(title)
            if items.isEmpty { empty }
            ForEach(items) { item in
                HStack(spacing: 8) {
                    if showIcon {
                        Group {
                            if let icon = AppIcon.image(for: item.bundleID) {
                                Image(nsImage: icon).resizable()
                            } else {
                                Text(String(item.name.prefix(1))).font(.caption2)
                            }
                        }
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                    }
                    Text(item.name).lineLimit(1)
                    Spacer()
                    Text(
                        "\(item.visits)× · \(DurationFormat.short(item.total)) · avg \(DurationFormat.short(item.average))"
                    )
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
                .font(.system(.caption, design: .monospaced))
                .accessibilityElement(children: .combine)
                DottedDivider()
            }
        }
    }

    private var transitions: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Most-used transitions")
            if report.transitions.isEmpty { empty }
            ForEach(report.transitions) { t in
                HStack {
                    Text("\(t.from) \(Text("→").foregroundStyle(BreadcrumbPalette.rose)) \(t.to)").lineLimit(
                        1)
                    Spacer()
                    Text("\(t.count)×").foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.system(.caption, design: .monospaced))
                .accessibilityElement(children: .combine)
                DottedDivider()
            }
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(.caption2, design: .monospaced, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private var empty: some View {
        Text("Nothing yet — keep moving around.").font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
    }
}
