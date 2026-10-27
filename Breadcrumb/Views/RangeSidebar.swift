import SwiftUI

struct RangeSidebar: View {
    @Binding var selection: DateRange

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(DateRange.allCases) { range in
                Button { selection = range } label: {
                    Text(range.rawValue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selection == range ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: 6))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == range ? .isSelected : [])
            }
            Spacer()
        }
        .padding(10)
    }
}
