import SwiftUI

enum Theme {
    static let background = Color("AppBackground")
    static let card = Color("AppCardBackground")
    static let warmOverlay = Color("AppWarmOverlay")
    static let borderBase = Color("AppBorderBase")
    static let borderHighlight = Color("AppBorderHighlight")

    static var titaniumGradient: LinearGradient {
        LinearGradient(
            colors: [borderBase, borderHighlight, borderBase],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct WarmBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Theme.background)
    }
}

extension View {
    func warmBackground() -> some View {
        modifier(WarmBackgroundModifier())
    }

    func titaniumBorder(cornerRadius: CGFloat = 14) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.titaniumGradient, lineWidth: 0.5)
        )
    }
}
