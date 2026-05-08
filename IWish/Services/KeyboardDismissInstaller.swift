import UIKit

/// Глобальный tap-to-dismiss клавиатуры.
/// Tap по любому месту окна (вне TextField/TextView/UIControl) скрывает клавиатуру.
/// Не блокирует обычные touch'и (cancelsTouchesInView=false) — кнопки и tap-цели работают как раньше.
enum KeyboardDismissInstaller {
    private static var didInstall = false

    @MainActor
    static func installIfNeeded() {
        guard !didInstall else { return }
        // Делаем небольшую задержку, чтобы UIWindow гарантированно появилось.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            attachToActiveWindow()
        }
    }

    @MainActor
    private static func attachToActiveWindow() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let window = scene.windows.first else {
            // Сцена ещё не готова — попробуем повторно.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                attachToActiveWindow()
            }
            return
        }

        let recognizer = UITapGestureRecognizer(target: KeyboardDismissTarget.shared,
                                                action: #selector(KeyboardDismissTarget.handleTap(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = KeyboardDismissTarget.shared
        recognizer.requiresExclusiveTouchType = false
        window.addGestureRecognizer(recognizer)
        didInstall = true
    }
}

private final class KeyboardDismissTarget: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissTarget()

    @objc func handleTap(_ gr: UITapGestureRecognizer) {
        guard gr.state == .ended else { return }
        gr.view?.endEditing(true)
    }

    // Не пропускать touch если он попал на input control или внутри клавиатуры.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        // Не реагируем на touch внутри активного редактируемого поля — иначе клава будет закрываться
        // прямо при тапе в тот же TextField (странное поведение).
        guard let view = touch.view else { return true }
        if view is UITextField || view is UITextView { return false }
        // Если touch попал на subview UITextField/UITextView (например clear button) — тоже игнорируем.
        var current: UIView? = view
        while let v = current {
            if v is UITextField || v is UITextView { return false }
            current = v.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Параллельно с любыми другими — не блокируем кнопки/skroll.
        return true
    }
}
