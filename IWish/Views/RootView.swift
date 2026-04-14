import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]

    var body: some View {
        NavigationStack {
            HomeView()
        }
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
