import SwiftUI

struct SyncStatusPullHeader: View {
    let state: SyncStatusService.State
    let pullOffset: CGFloat
    let isPermissionDenied: Bool
    var onRetry: (() -> Void)? = nil

    var body: some View {
        if isPermissionDenied {
            EmptyView()
        } else if isError {
            // Error/offline — always visible, tappable for retry
            HStack {
                Spacer()
                SyncStatusBadge(state: state, onTap: onRetry)
                Spacer()
            }
            .frame(height: 36)
        } else {
            // Synced/idle/syncing — hidden, revealed by pull
            let progress = min(1.0, max(0.0, pullOffset / 60))
            HStack {
                Spacer()
                SyncStatusBadge(state: state, onTap: nil)
                    .scaleEffect(progress)
                    .opacity(progress)
                Spacer()
            }
            .frame(height: pullOffset > 5 ? 36 * progress : 0)
            .clipped()
        }
    }

    private var isError: Bool {
        switch state {
        case .error, .offline: return true
        default: return false
        }
    }
}
