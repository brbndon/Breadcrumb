import Accessibility
import SwiftUI

/// Screen time as columns of crumbs: each filled dot is `crumbValue` seconds, drawn on the paper grid.
struct CrumbChart: View {
    let slots: [ScreenTimeSlot]
    let unit: Calendar.Component
    let crumbValue: TimeInterval
    /// Short name of the preceding period, such as "Yesterday"; nil hides its markers.
    let comparisonName: String?
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var width: CGFloat = 0
    @State private var hovered: Int?

    private let rowPitch: CGFloat = 14
    private let tooltipWidth: CGFloat = 156
    private var rows: Int { ScreenTimeTimeline.maxCrumbs }
    private var plotHeight: CGFloat { rowPitch * CGFloat(rows) }
    private var pitch: CGFloat { slots.isEmpty ? 0 : width / CGFloat(slots.count) }

    var body: some View {
        VStack(spacing: 8) {
            Canvas { context, size in drawPlot(context, size: size) }
                .frame(height: plotHeight)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    width = $0
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        let index = pitch > 0 ? Int(point.x / pitch) : -1
                        hovered = slots.indices.contains(index) ? index : nil
                    case .ended: hovered = nil
                    }
                }
                .overlay(alignment: .topLeading) { tooltip }
            Canvas { context, size in drawAxis(context, size: size) }
                .frame(height: 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityChartDescriptor(
            CrumbChartDescriptor(
                title: "Screen time by \(unit == .hour ? "hour" : "day")",
                axis: unit == .hour ? "Hour" : "Day",
                summary: accessibilitySummary, labels: slots.map(slotLabel),
                minutes: slots.map { $0.seconds / 60 }
            ))
    }

    // MARK: Drawing

    private func drawPlot(_ context: GraphicsContext, size: CGSize) {
        guard !slots.isEmpty else { return }
        let pitch = size.width / CGFloat(slots.count)
        let crumb = min(9, pitch * 0.58, rowPitch * 0.68)
        let guideInk = Color.primary.opacity(contrast == .increased ? 0.3 : 0.13)
        let futureInk = Color.primary.opacity(contrast == .increased ? 0.14 : 0.05)
        let markerInk = Color.primary.opacity(contrast == .increased ? 0.85 : 0.5)
        for (index, slot) in slots.enumerated() {
            let center = pitch * (CGFloat(index) + 0.5)
            let dimmed = hovered != nil && hovered != index
            let ink = BreadcrumbPalette.rose.opacity(dimmed ? 0.4 : 1)
            if hovered == index {
                let column = CGRect(x: center - pitch / 2 + 1, y: 0, width: pitch - 2, height: size.height)
                context.fill(Path(roundedRect: column, cornerRadius: 6), with: .color(.primary.opacity(0.05)))
            }
            let level = min(Double(rows), slot.seconds / crumbValue)
            if crumb >= 3 {
                let full = Int(level)
                let partial = level - Double(full)
                for row in 0..<rows {
                    let y = size.height - rowPitch * (CGFloat(row) + 0.5)
                    if row < full {
                        context.fill(dot(center, y, crumb), with: .color(ink))
                    } else if row == full && partial > 0.04 {
                        // Area tracks the remainder, so a quarter crumb reads as a quarter.
                        context.fill(
                            dot(center, y, max(2.5, crumb * partial.squareRoot())), with: .color(ink))
                    } else {
                        context.fill(dot(center, y, 2), with: .color(slot.isFuture ? futureInk : guideInk))
                    }
                }
            } else {
                let height = size.height * level / Double(rows)
                let bar = CGRect(
                    x: center - max(1, pitch * 0.3), y: size.height - height, width: max(1, pitch * 0.6),
                    height: height)
                context.fill(Path(roundedRect: bar, cornerRadius: min(2, bar.width / 2)), with: .color(ink))
            }
            if comparisonName != nil, let previous = slot.previousSeconds, previous > 0 {
                let y = size.height - rowPitch * min(Double(rows), previous / crumbValue)
                let half = min(8, pitch * 0.34)
                var tick = Path()
                tick.move(to: CGPoint(x: center - half, y: y))
                tick.addLine(to: CGPoint(x: center + half, y: y))
                context.stroke(
                    tick, with: .color(markerInk), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
    }

    private func drawAxis(_ context: GraphicsContext, size: CGSize) {
        guard !slots.isEmpty else { return }
        let pitch = size.width / CGFloat(slots.count)
        let stride = labelStride
        for (index, slot) in slots.enumerated() where index % stride == 0 {
            let text = context.resolve(
                Text(axisLabel(slot)).font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary))
            let half = text.measure(in: size).width / 2
            let x = min(max(pitch * (CGFloat(index) + 0.5), half), size.width - half)
            context.draw(text, at: CGPoint(x: x, y: 0), anchor: .top)
        }
    }

    private func dot(_ x: CGFloat, _ y: CGFloat, _ diameter: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter))
    }

    // MARK: Labels

    private var labelStride: Int {
        if unit == .hour { return 6 }
        if slots.count <= 7 { return 1 }
        return Int((Double(slots.count) / 7).rounded(.up))
    }

    private func axisLabel(_ slot: ScreenTimeSlot) -> String {
        if unit == .hour { return slot.id.formatted(.dateTime.hour()) }
        if slots.count <= 7 { return slot.id.formatted(.dateTime.weekday(.abbreviated)) }
        return slot.id.formatted(.dateTime.month(.abbreviated).day())
    }

    private func slotLabel(_ slot: ScreenTimeSlot) -> String {
        if unit == .hour {
            return
                "\(slot.id.formatted(.dateTime.hour().minute())) – \(slot.end.formatted(.dateTime.hour().minute()))"
        }
        return slot.id.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    @ViewBuilder private var tooltip: some View {
        if let hovered, slots.indices.contains(hovered) {
            let slot = slots[hovered]
            let center = pitch * (CGFloat(hovered) + 0.5)
            let right = center + pitch / 2 + 6
            let x = right + tooltipWidth <= width ? right : max(0, center - pitch / 2 - 6 - tooltipWidth)
            VStack(alignment: .leading, spacing: 3) {
                Text(slotLabel(slot)).font(.system(.caption2, design: .monospaced)).foregroundStyle(
                    .secondary)
                Text(slot.isFuture ? "Upcoming" : DurationFormat.short(slot.seconds))
                    .font(.system(.callout, design: .monospaced, weight: .semibold)).monospacedDigit()
                if let comparisonName, let previous = slot.previousSeconds {
                    Text("\(comparisonName): \(DurationFormat.short(previous))")
                        .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(width: tooltipWidth, alignment: .leading)
            .background(.background, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
            .offset(x: x)
            .allowsHitTesting(false)
        }
    }

    private var accessibilitySummary: String {
        let total = slots.reduce(0) { $0 + $1.seconds }
        var text =
            "Screen time by \(unit == .hour ? "hour" : "day"), \(DurationFormat.short(total)) in total."
        if let peak = slots.max(by: { $0.seconds < $1.seconds }), peak.seconds > 0 {
            text += " Busiest: \(slotLabel(peak)), \(DurationFormat.short(peak.seconds))."
        }
        return text
    }
}

/// Audio Graph data for VoiceOver, built from plain values so it stays off the main actor.
private struct CrumbChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let axis: String
    let summary: String
    let labels: [String]
    let minutes: [Double]

    func makeChartDescriptor() -> AXChartDescriptor {
        let series = AXDataSeriesDescriptor(
            name: "Screen time", isContinuous: false,
            dataPoints: zip(labels, minutes).map { AXDataPoint(x: $0, y: $1) })
        return AXChartDescriptor(
            title: title, summary: summary,
            xAxis: AXCategoricalDataAxisDescriptor(title: axis, categoryOrder: labels),
            yAxis: AXNumericDataAxisDescriptor(
                title: "Minutes", range: 0...max(1, minutes.max() ?? 0), gridlinePositions: []
            ) { "\(Int($0.rounded())) minutes" }, additionalAxes: [], series: [series])
    }
}
