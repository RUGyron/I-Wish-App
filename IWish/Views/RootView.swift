import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var detectedSystemScheme
    @Environment(\.appServices) private var services
    @Query private var settingsList: [AppSettings]

    var body: some View {
        NavigationStack {
            HomeView()
        }
        .fontDesign(.rounded)
        .toolbarBackground(Theme.warmOverlay, for: .navigationBar)
        .environment(\.systemColorScheme, detectedSystemScheme)
        .preferredColorScheme(activeSettings.themeMode.colorScheme)
        .animation(.easeInOut(duration: 0.35), value: activeSettings.themeMode)
        .onAppear {
            // Гарантируем что AppSettings существует в БД.
            if settingsList.isEmpty {
                _ = AppSettings.loadOrCreate(in: context)
            }
        }
        .task {
            // Firebase auth is auto-initialized via AuthService.init()
        }
        .toastOverlay()
    }

    private var activeSettings: AppSettings {
        settingsList.first ?? AppSettings()
    }
}
