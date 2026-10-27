import SwiftUI

struct RangeSidebar: View {
    @Binding var selection: DateRange
    @State private var hovered: DateRange?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(DateRange.allCases) { range in
                Button {
                    selection = range
                } label: {
                    Text(range.rawValue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Color.primary.opacity(selection == range ? 0.1 : (hovered == range ? 0.05 : 0)),
                            in: .rect(cornerRadius: 6)
                        )
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? range : nil }
                .accessibilityAddTraits(selection == range ? .isSelected : [])
            }
            Spacer()
        }
        .padding(10)
    }
}
