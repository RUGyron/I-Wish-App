import SwiftUI
import UIKit
import ObjectiveC

// MARK: - Public API
//
// Единый dismiss-toolbar над клавиатурой для всех TextField/TextEditor.
//
// Проблема: SwiftUI `.toolbar(.keyboard)` на iOS 26 рендерит пустую серую
// полоску над numeric pad / emoji keyboard / TextEditor — кнопка не отображается,
// либо bar появляется без содержимого. Это видно как «белая/серая полоска» которая
// прокручивается вместе с клавой.
//
// Решение: глобальный UIKit `inputAccessoryView` с кнопкой dismiss, который
// устанавливается через swizzling `becomeFirstResponder` для UITextField и UITextView.
// Работает для всех типов клавиатур, включая decimalPad / numberPad / emoji.
//
// Активация: вызвать `KeyboardDismissBarInstaller.install()` один раз при старте
// приложения (в `IWishApp.init()` или похоже).

enum KeyboardDismissBarInstaller {
    static func install() {
        UITextField.iwish_swizzleBecomeFirstResponder()
        UITextView.iwish_swizzleBecomeFirstResponder()
    }
}

// MARK: - Accessory view factory

private enum KeyboardDismissAccessory {
    /// Создаёт UIToolbar с одной кнопкой `keyboard.chevron.compact.down` справа.
    static func make() -> UIToolbar {
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        bar.barStyle = .default
        bar.isTranslucent = true
        bar.sizeToFit()

        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let icon = UIImage(systemName: "keyboard.chevron.compact.down")
        let dismiss = UIBarButtonItem(
            image: icon,
            style: .plain,
            target: KeyboardDismissActionTarget.shared,
            action: #selector(KeyboardDismissActionTarget.dismissKeyboard)
        )
        dismiss.accessibilityLabel = "Скрыть клавиатуру"

        bar.items = [flex, dismiss]
        return bar
    }
}

// Объект-таргет для UIBarButtonItem (нужен NSObject).
private final class KeyboardDismissActionTarget: NSObject {
    static let shared = KeyboardDismissActionTarget()

    @objc func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}

// MARK: - Swizzling: UITextField

private extension UITextField {
    static func iwish_swizzleBecomeFirstResponder() {
        struct Once { static var done = false }
        guard !Once.done else { return }
        Once.done = true

        let original = #selector(becomeFirstResponder)
        let swizzled = #selector(iwish_becomeFirstResponderInjectingAccessory)
        guard
            let originalMethod = class_getInstanceMethod(UITextField.self, original),
            let swizzledMethod = class_getInstanceMethod(UITextField.self, swizzled)
        else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    @objc func iwish_becomeFirstResponderInjectingAccessory() -> Bool {
        if inputAccessoryView == nil {
            inputAccessoryView = KeyboardDismissAccessory.make()
        }
        // После swizzle этот вызов уходит в оригинальную реализацию.
        return iwish_becomeFirstResponderInjectingAccessory()
    }
}

// MARK: - Swizzling: UITextView

private extension UITextView {
    static func iwish_swizzleBecomeFirstResponder() {
        struct Once { static var done = false }
        guard !Once.done else { return }
        Once.done = true

        let original = #selector(becomeFirstResponder)
        let swizzled = #selector(iwish_becomeFirstResponderInjectingAccessory)
        guard
            let originalMethod = class_getInstanceMethod(UITextView.self, original),
            let swizzledMethod = class_getInstanceMethod(UITextView.self, swizzled)
        else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    @objc func iwish_becomeFirstResponderInjectingAccessory() -> Bool {
        if inputAccessoryView == nil {
            inputAccessoryView = KeyboardDismissAccessory.make()
        }
        return iwish_becomeFirstResponderInjectingAccessory()
    }
}
