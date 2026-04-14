import SwiftUI

enum Theme {
    static let background = Color("AppBackground")
    static let card = Color("AppCardBackground")
    static let warmOverlay = Color("AppWarmOverlay")
}

/// Applies warm-tinted background to Form/List views.
/// Usage: `.warmBackground()` on Form or List.
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
}
