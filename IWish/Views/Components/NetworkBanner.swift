import SwiftUI

/// Persistent network-status bar. Спокойная тонкая полоска, не тост-формат.
///
/// Дизайн (2026-05-18 после фидбека Влада):
/// - Тосты-формат поверх всего UI неуместен для долгого состояния. Заменён на тонкую
///   полосу-ленту прямо под navigation bar (как iOS-системный VPN/recording bar).
/// - Высота ~28pt, background `.thinMaterial`, без shadow и больших rounded углов.
/// - Pinned внизу status bar / над nav title — приземлённый indicator без отвлечения.
/// - `allowsHitTesting(false)` — touch проходит насквозь.
struct NetworkBanner: View {
    let monitor: NetworkMonitor

    var body: some View {
        if monitor.isBlocked {
            VStack(spacing: 0) {
                // Pin под inline navigation bar (44pt + safe area sometimes already accounted).
                Spacer().frame(height: 44)

                HStack(spacing: 6) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)

                    Text("No connection")
                        .font(.caption.weight(.regular))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.thinMaterial)
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.5)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("No connection. Attempting to reconnect.")

                Spacer()
            }
            .allowsHitTesting(false)
            .animation(.spring(duration: 0.3, bounce: 0.0), value: monitor.isBlocked)
        }
    }
}
