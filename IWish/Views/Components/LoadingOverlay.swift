import SwiftUI

/// Universal full-screen loading overlay. Shows a blur + spinner over any content.
/// Usage: `.loadingOverlay(isLoading)` on any view.
struct LoadingOverlay: ViewModifier {
    let isLoading: Bool

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!isLoading)
            .overlay {
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.15)
                            .ignoresSafeArea()
                        ProgressView()
                            .scaleEffect(1.3)
                            .tint(.primary)
                            .padding(24)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isLoading)
    }
}

extension View {
    func loadingOverlay(_ isLoading: Bool) -> some View {
        modifier(LoadingOverlay(isLoading: isLoading))
    }
}
