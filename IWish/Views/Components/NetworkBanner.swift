import SwiftUI

/// Top-banner поверх всего интерфейса когда сеть нестабильна.
///
/// Показывается только когда `NetworkMonitor.isBlocked == true` — после N подряд
/// network-failures (threshold). Не блокирует чтение/scroll, только сигнализирует.
/// При восстановлении (M подряд successes) banner плавно исчезает.
struct NetworkBanner: View {
    let monitor: NetworkMonitor

    var body: some View {
        if monitor.isBlocked {
            HStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.body.weight(.semibold))
                Text("Нет соединения")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.red.opacity(0.92), in: RoundedRectangle(cornerRadius: 0))
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Нет соединения. Идёт попытка восстановления.")
        }
    }
}

#Preview {
    @Previewable @State var monitor = NetworkMonitor()
    return VStack {
        NetworkBanner(monitor: monitor)
        Button("Toggle blocked") {
            // Test only — real logic is via recordError/recordSuccess
            if monitor.isBlocked {
                monitor.recordSuccess()
                monitor.recordSuccess()
            } else {
                monitor.recordError(URLError(.notConnectedToInternet))
                monitor.recordError(URLError(.notConnectedToInternet))
                monitor.recordError(URLError(.notConnectedToInternet))
            }
        }
        Spacer()
    }
}
