import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var detectedSystemScheme
    @Environment(\.appServices) private var services
    @Query private var settingsList: [AppSettings]
    @State private var didConfigure = false

    var body: some View {
        Group {
            if services.auth.isLoading {
                splashView
            } else if !services.auth.isAuthenticated {
                signInView
            } else {
                mainContent
            }
        }
        .fontDesign(.rounded)
        .environment(\.systemColorScheme, detectedSystemScheme)
        .preferredColorScheme(activeSettings.themeMode.colorScheme)
        .animation(.easeInOut(duration: 0.8), value: activeSettings.themeMode)
        .onAppear {
            if settingsList.isEmpty {
                _ = AppSettings.loadOrCreate(in: context)
            }
            if !didConfigure {
                services.configure(modelContext: context)
                // Однократно сносим локальный store + Keychain после перехода на E2E:
                // старая Firestore-схема несовместима с новой (encryptedPayload), поэтому
                // тянуть будем только то, что появилось в новом формате после миграции.
                services.data?.wipeLocalIfNeeded()
                didConfigure = true
            }
        }
        .toastOverlay()
    }

    private var mainContent: some View {
        NavigationStack {
            HomeView()
        }
        .toolbarBackground(Theme.warmOverlay, for: .navigationBar)
        .task {
            await services.data?.refreshWishlists()
        }
    }

    private var splashView: some View {
        VStack(spacing: 16) {
            Image(systemName: "gift.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    private var signInView: some View {
        SignInWithAppleSheet { result in
            Task {
                try? await services.auth.handleSignInWithApple(result: result)
            }
        }
    }

    private var activeSettings: AppSettings {
        settingsList.first ?? AppSettings()
    }
}
