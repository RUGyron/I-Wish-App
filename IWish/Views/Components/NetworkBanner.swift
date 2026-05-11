import SwiftUI

/// Лаконичный banner потери сети + блокирующий overlay поверх всего UI.
///
/// Дизайн (после правок Влада 2026-05-11):
/// - Стиль как у тостов: `ultraThinMaterial`, rounded card, нейтральный цвет, без агрессивного red.
/// - Правильное размещение: НЕ в safe area, с padding от top.
/// - Блокирует UI: полупрозрачный backdrop consume'ит touches пока сеть нестабильна.
///   Юзер видит свои локальные данные подсвеченным, но не может тапать — это однозначный
///   сигнал "сейчас ничего сделать нельзя, ждём сеть".
///
/// Полностью прозрачен пока `monitor.isBlocked == false`.
struct NetworkBanner: View {
    let monitor: NetworkMonitor

    var body: some View {
        if monitor.isBlocked {
            ZStack(alignment: .top) {
                // Backdrop — мягкий, но consume'ит touches (UI залочен).
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .contentShape(Rectangle()) // hit-test всю площадь — блокировка тапов

                // Карточка banner — лаконичная, в стиле тостов.
                HStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("Нет соединения")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    ProgressView()
                        .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8) // отступ от safe-area top — RootView передаёт ниже status bar
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Нет соединения. Идёт попытка восстановления.")
            }
            .animation(.spring(duration: 0.3, bounce: 0.15), value: monitor.isBlocked)
        }
    }
}
