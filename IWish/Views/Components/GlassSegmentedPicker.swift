import SwiftUI

struct GlassSegmentedPicker<T: Hashable & CaseIterable & Identifiable, Content: View>: View where T.AllCases: RandomAccessCollection {
    @Binding var selection: T
    @ViewBuilder let content: (T) -> Content
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 4) {
            ForEach(T.allCases) { item in
                let isSelected = selection == item
                content(item)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .matchedGeometryEffect(id: "selection", in: animation)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selection = item
                        }
                    }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemFill))
        )
    }
}
