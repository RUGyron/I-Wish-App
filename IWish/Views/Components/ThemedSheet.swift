import SwiftUI
import SwiftData

private struct ThemedSheetModifier: ViewModifier {
    @Query private var settingsList: [AppSettings]

    private var resolved: ColorScheme {
        let mode = settingsList.first?.themeMode ?? .system
        switch mode {
        case .light: return .light
        case .dark:  return .dark
        case .system:
            return UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
        }
    }

    func body(content: Content) -> some View {
        content.preferredColorScheme(resolved)
    }
}

extension View {
    func applyTheme() -> some View {
        modifier(ThemedSheetModifier())
    }
}
