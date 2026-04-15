import SwiftUI

struct SyncStatusPullHeader: View {
    let state: SyncStatusService.State
    let scrollOffset: CGFloat // positive when pulled down
    let isDiscoverabilityDenied: Bool
    var onRetry: (() -> Void)? = nil

    var body: some View {
        if isDiscoverabilityDenied {
            // Never show sync badge when discoverability denied
            EmptyView()
        } else {
            let shouldShow = shouldForceShow || scrollOffset > 20
            let pullProgress = min(1.0, max(0.0, scrollOffset / 80))

            HStack {
                Spacer()
                if shouldShow {
                    SyncStatusBadge(state: state, onTap: onRetry)
                        .scaleEffect(shouldForceShow ? 1.0 : pullProgress)
                        .opacity(shouldForceShow ? 1.0 : pullProgress)
                        .transition(.scale.combined(with: .opacity))
                }
                Spacer()
            }
            .frame(height: shouldShow ? 40 : 0)
            .clipped()
            .animation(.spring(response: 0.3), value: shouldShow)
        }
    }

    private var shouldForceShow: Bool {
        switch state {
        case .syncing, .error, .offline: return true
        default: return false
        }
    }
}
