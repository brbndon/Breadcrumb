import SwiftUI

enum BreadcrumbPalette {
    static let rose = Color(red: 0.68, green: 0.39, blue: 0.44)
}

struct PaperCanvas: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        let dark = scheme == .dark
        ZStack {
            dark
                ? Color(red: 24 / 255, green: 19 / 255, blue: 15 / 255)
                : Color(red: 252 / 255, green: 248 / 255, blue: 238 / 255)
            Canvas { context, size in
                var dots = Path()
                for x in stride(from: 0.0, to: size.width, by: 6) {
                    for y in stride(from: 0.0, to: size.height, by: 6) {
                        dots.addEllipse(in: CGRect(x: x, y: y, width: 1, height: 1))
                    }
                }
                context.fill(
                    dots,
                    with: .color((dark ? Color.white : .black).opacity(contrast == .increased ? 0.12 : 0.045))
                )
            }
        }.accessibilityHidden(true)
    }
}

struct DottedDivider: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: geometry.size.width, y: 0))
            }.stroke(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
        }.frame(height: 1).accessibilityHidden(true)
    }
}
