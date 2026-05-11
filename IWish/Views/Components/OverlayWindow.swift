import SwiftUI
import UIKit

/// Прозрачное UIWindow поверх всего UI (включая sheet'ы и confirmationDialog'и).
/// Hosting'аются banner потери сети и тосты — они всегда сверху, даже когда открыт modal.
///
/// **Зачем:** на iOS sheet'ы рендерятся в собственном UIWindow слое выше root window.
/// `.overlay()` / `.toastOverlay()` на root view не видны когда показан sheet.
/// Чтобы banner и toast имели приоритет над любыми sheet'ами, мы создаём
/// дополнительный UIWindow на `.alert + 1` level — он гарантированно выше modals.
///
/// **Hit-testing:** PassthroughWindow override'ит `hitTest` — touches пропускаются
/// к нижним окнам везде кроме реальных subview'ов banner/toast. Юзер не теряет
/// возможность взаимодействовать с UI под overlay'ем.
final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        // Если попали ровно в корневой пустой контейнер — пропустить тач к нижнему окну.
        // Если в subview (banner / toast) — обработать здесь.
        if hit === rootViewController?.view {
            return nil
        }
        return hit
    }
}

@MainActor
final class OverlayWindowController {
    static let shared = OverlayWindowController()
    private var window: PassthroughWindow?

    func installIfNeeded(on scene: UIWindowScene) {
        guard window == nil else { return }
        let w = PassthroughWindow(windowScene: scene)
        w.windowLevel = .alert + 1  // Выше любых system alert'ов и .alert.
        w.backgroundColor = .clear
        w.isOpaque = false
        let host = UIHostingController(rootView: OverlayRootView())
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        w.rootViewController = host
        w.isHidden = false
        window = w
    }
}

/// Корневой view overlay-window. Содержит banner потери сети и тосты.
/// При отсутствии активного banner/toast — полностью прозрачен и пропускает touches.
///
/// **⚠ НЕ ДОБАВЛЯТЬ:** `.background(...)`, `.contentShape(Rectangle())`, `.frame(...)` с
/// solid color на корневой ZStack — это создаст hit-testable backing view, и passthrough
/// в PassthroughWindow перестанет работать. Юзер не сможет тапать UI под overlay'ем.
/// Banner / backdrop / toast уже имеют собственный `.background()` или `.contentShape()` —
/// там hit-testing работает осмысленно.
struct OverlayRootView: View {
    private let monitor = AppServices.shared.networkMonitor
    private let toastManager = ToastManager.shared

    var body: some View {
        ZStack(alignment: .top) {
            // 1. NetworkBanner: при isBlocked показывает backdrop (на весь экран, lock UI)
            //    + карточку banner. Backdrop поглощает touches — UI залочен.
            NetworkBanner(monitor: monitor)

            // 2. Toast: всегда поверх banner (выше z-index), уважает safe area сверху.
            //    При активном banner тост встаёт ниже карточки banner за счёт extra-padding.
            if let toast = toastManager.current {
                ToastBannerView(toast: toast) {
                    toastManager.dismiss()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                // padding.top: 8 (от safe area) + extra 64 если banner показан, чтобы не накладывались
                .padding(.top, monitor.isBlocked ? 72 : 8)
                .zIndex(2)
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.15), value: toastManager.current?.id)
        .animation(.spring(duration: 0.3, bounce: 0.15), value: monitor.isBlocked)
    }
}

/// Helper: монтирует overlay window когда RootView появляется (через scene reference).
struct OverlayWindowInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            if let scene = v.window?.windowScene {
                OverlayWindowController.shared.installIfNeeded(on: scene)
            }
        }
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            if let scene = uiView.window?.windowScene {
                OverlayWindowController.shared.installIfNeeded(on: scene)
            }
        }
    }
}

extension View {
    /// Устанавливает overlay-window (banner + toast) поверх всех sheet'ов.
    /// Подключается один раз на корневом view приложения.
    func installOverlayWindow() -> some View {
        background(OverlayWindowInstaller().frame(width: 0, height: 0))
    }
}
