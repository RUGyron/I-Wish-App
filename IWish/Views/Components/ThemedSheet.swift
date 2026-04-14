import SwiftUI
import SwiftData

/// Модификатор для пробрасывания темы из AppSettings в sheet'ы.
/// iOS sheets создают отдельную scene и не наследуют preferredColorScheme от родителя.
private struct ThemedSheetModifier: ViewModifier {
    @Query private var settingsList: [AppSettings]

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(
                (settingsList.first?.themeMode ?? .system).colorScheme
            )
    }
}

extension View {
    /// Применяет текущую тему из AppSettings. Использовать на корневой вьюхе каждого sheet'а.
    func applyTheme() -> some View {
        modifier(ThemedSheetModifier())
    }
}
