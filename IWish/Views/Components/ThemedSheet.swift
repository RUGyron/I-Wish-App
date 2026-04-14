import SwiftUI
import SwiftData

// Custom environment key for the unmodified system color scheme
private struct SystemColorSchemeKey: EnvironmentKey {
    static let defaultValue: ColorScheme = .light
}

extension EnvironmentValues {
    var systemColorScheme: ColorScheme {
        get { self[SystemColorSchemeKey.self] }
        set { self[SystemColorSchemeKey.self] = newValue }
    }
}

private struct ThemedSheetModifier: ViewModifier {
    @Query private var settingsList: [AppSettings]
    @Environment(\.systemColorScheme) private var systemScheme

    func body(content: Content) -> some View {
        let mode = settingsList.first?.themeMode ?? .system
        content
            .preferredColorScheme(mode == .system ? systemScheme : mode.colorScheme)
    }
}

extension View {
    func applyTheme() -> some View {
        modifier(ThemedSheetModifier())
    }
}
