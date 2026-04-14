import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var detectedSystemScheme
    @Query private var settingsList: [AppSettings]

    var body: some View {
        NavigationStack {
            HomeView()
        }
        .toolbarBackground(Theme.warmOverlay, for: .navigationBar)
        .environment(\.systemColorScheme, detectedSystemScheme)
        .preferredColorScheme(activeSettings.themeMode.colorScheme)
        .onAppear {
            // Гарантируем что AppSettings существует в БД.
            if settingsList.isEmpty {
                _ = AppSettings.loadOrCreate(in: context)
            }
        }
    }

    private var activeSettings: AppSettings {
        settingsList.first ?? AppSettings()
    }
}
