import SwiftUI

struct SyncStatusPullHeader: View {
    let state: SyncStatusService.State
    let scrollOffset: CGFloat
    let isDiscoverabilityDenied: Bool
    var onRetry: (() -> Void)? = nil

    var body: some View {
        if isDiscoverabilityDenied {
            EmptyView()
        } else {
            let forceVisible = isActiveOrError
            let pullVisible = scrollOffset > 30
            let visible = forceVisible || pullVisible
            let scale = forceVisible ? 1.0 : min(1.0, max(0.0, (scrollOffset - 10) / 60))

            VStack {
                if visible {
                    SyncStatusBadge(state: state, onTap: onRetry)
                        .scaleEffect(scale)
                        .opacity(scale)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: forceVisible ? 36 : 0)
            .clipped()
            .animation(.spring(response: 0.3), value: visible)
        }
    }

    private var isActiveOrError: Bool {
        switch state {
        case .syncing, .error, .offline: return true
        case .idle, .synced: return false
        }
    }
}
