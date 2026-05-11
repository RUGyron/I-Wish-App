import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var detectedSystemScheme
    @Environment(\.appServices) private var services
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query private var settingsList: [AppSettings]
    @State private var didConfigure = false
    @State private var rc = RemoteConfigService()

    var body: some View {
        Group {
            if rc.isLoading || services.auth.isLoading {
                splashView
            } else if rc.requiresForceUpdate {
                ForceUpdateBlockingView(message: rc.forceUpdateMessage)
            } else if !services.auth.isAuthenticated {
                signInView
            } else if services.auth.requiresNameRecovery {
                NameRecoveryView()
            } else {
                mainContent
            }
        }
        .fontDesign(.rounded)
        .environment(\.systemColorScheme, detectedSystemScheme)
        .preferredColorScheme(activeSettings.themeMode.colorScheme)
        // Theme switching — короче анимация (0.8 → 0.3), глобальная на корне приводит
        // к замедленной анимации любых state-changes которые случаются параллельно.
        .animation(.easeInOut(duration: 0.3), value: activeSettings.themeMode)
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
        .task {
            await rc.fetch()
        }
        // Banner потери сети + тосты живут в отдельном UIWindow поверх всех sheet'ов.
        // .toastOverlay() и .overlay(NetworkBanner) НЕ используются — они бы были под sheet'ами.
        .installOverlayWindow()
    }

    @ViewBuilder
    private var mainContent: some View {
        if sizeClass == .regular {
            // iPad / iPhone landscape — split layout
            NavigationSplitView {
                HomeView()
                    .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 500)
            } detail: {
                emptyDetail
            }
            .navigationSplitViewStyle(.balanced)
            .toolbarBackground(Theme.warmOverlay, for: .navigationBar)
            .task {
                await services.data?.refreshWishlists()
            }
        } else {
            // iPhone portrait — push stack
            NavigationStack {
                HomeView()
            }
            .toolbarBackground(Theme.warmOverlay, for: .navigationBar)
            .task {
                await services.data?.refreshWishlists()
            }
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("Выберите список")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
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
