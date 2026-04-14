import SwiftUI

/// Кастомный picker для ItemTier с динамическими размерами баблов.
/// Active бабл показывает emoji + текст, inactive — только emoji.
struct TierPicker: View {
    @Binding var selection: ItemTier
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ItemTier.allCases) { tier in
                Button {
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                        selection = tier
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(tier.icon)
                            .font(.body)
                        if tier == selection {
                            Text(tier.label)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                                    removal: .scale(scale: 0.8).combined(with: .opacity)
                                ))
                        }
                    }
                    .padding(.horizontal, tier == selection ? 14 : 10)
                    .padding(.vertical, 8)
                    .background {
                        if tier == selection {
                            Capsule()
                                .fill(.tint.opacity(0.15))
                                .matchedGeometryEffect(id: "tier_bg", in: animation)
                        } else {
                            Capsule()
                                .fill(Color(.tertiarySystemFill))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tier.icon) \(tier.label)")
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    @Previewable @State var tier: ItemTier = .maybe
    TierPicker(selection: $tier)
        .padding()
}
