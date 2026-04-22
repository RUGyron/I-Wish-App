import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var detectedSystemScheme
    @Environment(\.appServices) private var services
    @Query private var settingsList: [AppSettings]

    var body: some View {
        Group {
            if !services.auth.isAuthenticated && !services.auth.skippedSignIn {
                signInView
            } else {
                mainContent
            }
        }
        .fontDesign(.rounded)
        .environment(\.systemColorScheme, detectedSystemScheme)
        .preferredColorScheme(activeSettings.themeMode.colorScheme)
        .animation(.easeInOut(duration: 0.35), value: activeSettings.themeMode)
        .onAppear {
            if settingsList.isEmpty {
                _ = AppSettings.loadOrCreate(in: context)
            }
        }
        .toastOverlay()
    }

    private var mainContent: some View {
        NavigationStack {
            HomeView()
        }
        .toolbarBackground(Theme.warmOverlay, for: .navigationBar)
    }

    private var signInView: some View {
        SignInWithAppleSheet { result in
            Task {
                try? await services.auth.handleSignInWithApple(result: result)
            }
        } onSkip: {
            services.auth.skippedSignIn = true
        }
    }

    private var activeSettings: AppSettings {
        settingsList.first ?? AppSettings()
    }
}
