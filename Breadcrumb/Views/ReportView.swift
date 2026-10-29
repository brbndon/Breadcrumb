import SwiftUI

struct ReportView: View {
    @Bindable var explorer: HistoryExplorer
    private var report: Report { explorer.report }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if explorer.filter.isActive {
                    Text(
                        "Report: whole selected period. Journey filters apply only to visits below the search field."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) { statistics }
                    VStack(alignment: .leading, spacing: 12) { statistics }
                }
                DisclosureGroup("About estimated time") {
                    Text(
                        "Each recorded visit contributes at most five minutes, capped from its original start before clipping to this period. The newest ongoing visit contributes zero until its duration can be resolved. This is an estimate, not measured productive time."
                    )
                    Text(
                        "Recorded visit duration in the journey is uncapped and can include unattended time when idle pausing was disabled. Ongoing means its duration is unknown."
                    )
                }.font(.caption)
                Picker("Sort apps and sites by", selection: $explorer.sort) {
                    ForEach(ReportSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                section("Apps", report.topApps, kind: .apps, expanded: $explorer.showAllApps)
                section("Sites", report.topSites, kind: .sites, expanded: $explorer.showAllSites)
                transitions
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var statistics: some View {
        stat("Switches", "\(report.switches)")
        stat("Apps", "\(report.apps)")
        stat("Estimated time", "\(report.activeMinutes)m")
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .monospaced, weight: .bold)).monospacedDigit()
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func section(
        _ title: String, _ items: [RankedItem], kind: HistoryKindFilter, expanded: Binding<Bool>
    ) -> some View {
        let sorted = ReportBuilder.rankedItems(items, by: explorer.sort)
        let visible = expanded.wrappedValue ? sorted : Array(sorted.prefix(6))
        return VStack(alignment: .leading, spacing: 8) {
            heading(title)
            if items.isEmpty { empty }
            ForEach(visible) { item in
                Button {
                    explorer.select(item, kind: kind)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            if explorer.filter.nodeKey == item.key {
                                Image(systemName: "checkmark").accessibilityHidden(true)
                            }
                            Text(item.name).multilineTextAlignment(.leading)
                        }
                        if kind == .apps, let bundle = item.bundleID {
                            Text(bundle).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                        }
                        Text(
                            "\(item.visits) visits · \(DurationFormat.short(item.total)) estimated · avg \(DurationFormat.short(item.average))"
                        )
                        .foregroundStyle(.secondary).multilineTextAlignment(.leading).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    .background(
                        Color.primary.opacity(explorer.filter.nodeKey == item.key ? 0.08 : 0),
                        in: .rect(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .accessibilityLabel(
                    "\(item.name), \(item.bundleID ?? item.key), \(item.visits) visits, \(DurationFormat.short(item.total)) estimated time"
                )
                .accessibilityHint("Show this entry’s visits in the journey")
                .accessibilityAddTraits(explorer.filter.nodeKey == item.key ? .isSelected : [])
                DottedDivider()
            }
            if items.count > 6 {
                Button(
                    expanded.wrappedValue
                        ? "Show fewer \(title.lowercased())" : "Show all \(items.count) \(title.lowercased())"
                ) {
                    expanded.wrappedValue.toggle()
                }
            }
        }
    }

    private var transitions: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Most-used transitions")
            if report.transitions.isEmpty { empty }
            ForEach(report.transitions) { transition in
                HStack(alignment: .top) {
                    Text("\(transition.from) → \(transition.to)")
                    Spacer()
                    Text("\(transition.count)×").foregroundStyle(.secondary).monospacedDigit()
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
        Text("No recorded history").font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
    }
}
