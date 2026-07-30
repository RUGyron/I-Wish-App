import SwiftUI

/// Helper-view: рисует один из 4 стилей "pending sync" indicator на основе AppSettings.
/// Используется для item rows и wishlist tiles одинаково.
///
/// Style "pill" — самый явный, для тех кто хочет максимум ясности.
/// Style "stripe"/"clock"/"dot" — более лаконичные варианты.
enum PendingIndicatorPlacement {
    case itemRowCover   // overlay на cover в item-row (52pt)
    case itemRowSubtitle // под title в item-row, рядом с meta
    case tileCorner      // правый-верхний угол tile (большой)
}

struct PendingIndicator: View {
    let style: PendingIndicatorStyle
    let placement: PendingIndicatorPlacement
    let isPending: Bool

    private var accent: Color { Color.orange }

    var body: some View {
        if !isPending {
            EmptyView()
        } else {
            switch style {
            case .pill:
                pillView
            case .stripe:
                // Полоска рисуется не здесь, а через wrapper в caller (overlayStripe).
                // Для preview покажем dot.
                stripeProxyView
            case .clock:
                clockView
            case .dot:
                dotView
            }
        }
    }

    @ViewBuilder
    private var pillView: some View {
        switch placement {
        case .tileCorner:
            HStack(spacing: 5) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
                    .tint(.white)
                Text("Waiting for network")
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(.white)
            .background(accent.opacity(0.95), in: Capsule())
            .padding(8)
        case .itemRowSubtitle:
            HStack(spacing: 5) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
                    .tint(accent)
                Text("Waiting for network")
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(accent)
            .background(accent.opacity(0.15), in: Capsule())
            .overlay(Capsule().stroke(accent.opacity(0.4), lineWidth: 0.5))
        case .itemRowCover:
            // На cover слишком тесно для pill → подставим dot как fallback.
            dotView
        }
    }

    private var clockView: some View {
        Image(systemName: "clock.arrow.circlepath")
            .font(.system(size: placement == .tileCorner ? 14 : 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(placement == .tileCorner ? 6 : 4)
            .background(accent.opacity(0.9), in: Circle())
            .padding(placement == .tileCorner ? 8 : 2)
    }

    private var dotView: some View {
        Circle()
            .fill(accent)
            .frame(width: placement == .tileCorner ? 12 : 10, height: placement == .tileCorner ? 12 : 10)
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
            .padding(placement == .tileCorner ? 10 : 2)
    }

    /// Для stripe — caller рисует полосу сам (через `.overlay(alignment: .leading)` в row),
    /// а здесь рисуем мини-precision-icon для preview/cover контекстов.
    private var stripeProxyView: some View {
        Rectangle()
            .fill(accent)
            .frame(width: 3)
            .clipShape(RoundedRectangle(cornerRadius: 1.5))
    }

    /// Модификатор для всего row — применяет стиль на уровне всей строки,
    /// если style требует full-row treatment (например, .clock делает row faded).
    static func rowOpacity(style: PendingIndicatorStyle, isPending: Bool) -> Double {
        guard isPending else { return 1.0 }
        return style == .clock ? 0.55 : 1.0
    }
}

/// Helper-modifier: для item row / tile накладывает стиль `stripe` через leading-border
/// (рисуется поверх существующей tier-полоски). На .pill/.clock/.dot — no-op.
struct PendingStripeOverlay: ViewModifier {
    let style: PendingIndicatorStyle
    let isPending: Bool

    func body(content: Content) -> some View {
        if isPending && style == .stripe {
            content.overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 4)
            }
        } else {
            content
        }
    }
}

extension View {
    /// Применяет stripe-overlay поверх view если выбран стиль "stripe" и item/tile pending.
    func pendingStripe(style: PendingIndicatorStyle, isPending: Bool) -> some View {
        modifier(PendingStripeOverlay(style: style, isPending: isPending))
    }
}
