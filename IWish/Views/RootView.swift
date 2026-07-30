import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var detectedSystemScheme
    @Environment(\.appServices) private var services
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settingsList: [AppSettings]
    @Query private var allWishlists: [Wishlist]
    @State private var didConfigure = false
    @State private var rc = RemoteConfigService()
    /// Push deep-link: программно открываемый wishlist (+ опционально карточка желания).
    /// nil → ничего не открыто. Сброс в nil происходит автоматически при pop (navigationDestination(item:)).
    @State private var deeplinkWishlist: Wishlist?
    @State private var deeplinkItemID: String?

    var body: some View {
        Group {
            // Splash снимается как только auth ready. RemoteConfig fetch'ится в фоне —
            // он нужен только для force-update gate (offline-юзер всё равно обновиться не может),
            // незачем держать юзера на splash из-за этого. Если RC потом скажет "need update" —
            // showим ForceUpdateBlockingView поверх main UI (UI уже доступен к моменту прихода RC).
            if services.auth.isLoading {
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
        .task {
            // Если push permission уже granted — регистрируемся при старте.
            // Если notDetermined — не запрашиваем тут, юзер сам в Settings включит.
            await services.push.bootstrapIfAuthorized()
            services.push.onDeeplink { deeplink in
                Task { @MainActor in
                    switch deeplink {
                    case .wishlist(let id):
                        await resolveAndNavigate(wishlistID: id, itemID: nil)
                    case .item(let wlID, let itemID):
                        await resolveAndNavigate(wishlistID: wlID, itemID: itemID)
                    }
                }
            }
        }
        .onChange(of: services.auth.isAuthenticated) { _, isAuth in
            Task { await processPendingShares() }
            // Синкаем глобальную настройку уведомлений в Firestore когда auth готов — чтобы CF
            // знал текущее значение даже если юзер выключал тоггл до этого билда (тогда поля не было).
            if isAuth {
                services.push.syncPushEnabledPreference(activeSettings.pushNotificationsEnabled)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await processPendingShares() }
                syncWishlistsCacheIfNeeded()
                // Заход в приложение: чистим доставленные уведы + системный badge + серверный
                // unread-счётчик (баг #5: уведы висели, бейдж не сбрасывался/не совпадал).
                services.push.clearDeliveredAndResetBadge()
                ReviewService.maybeRequestReviewOnForeground()
            }
        }
        .onChange(of: allWishlists.count) { _, _ in syncWishlistsCacheIfNeeded() }
        .onChange(of: allWishlists.map { "\($0.id)-\($0.name)-\($0.updatedAt)-\($0.isArchived)" }) { _, _ in
            syncWishlistsCacheIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .iwishPushDeeplink)) { notif in
            guard let url = notif.object as? URL else { return }
            handlePushDeeplinkURL(url)
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
                    .navigationDestination(item: $deeplinkWishlist) { wl in
                        WishlistDetailView(wishlist: wl, initialItemID: deeplinkItemID)
                    }
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
                    .navigationDestination(item: $deeplinkWishlist) { wl in
                        WishlistDetailView(wishlist: wl, initialItemID: deeplinkItemID)
                    }
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
            Text("Select a list")
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

    /// Обрабатывает очередь Share Extension. Триггерится при app становится active и при login.
    @MainActor
    private func processPendingShares() async {
        guard didConfigure else { return }
        let processor = PendingSharesProcessor(services: services, modelContext: context)
        await processor.processAll()
    }

    /// Синкает snapshot wishlists в App Group cache. Вызывается при изменении списка
    /// (создание / удаление / архивация / редактирование) — picker в Share Extension всегда свежий.
    @MainActor
    private func syncWishlistsCacheIfNeeded() {
        WishlistsCacheSync.sync(from: allWishlists)
    }

    /// Декодирует iwish://wishlist/{id} или iwish://wishlist/{id}/item/{itemID} в pending state.
    /// HomeView/WishlistDetailView отвечают за реакцию.
    private func handlePushDeeplinkURL(_ url: URL) {
        guard url.scheme == "iwish", url.host() == "wishlist" else { return }
        let parts = url.path.split(separator: "/").map(String.init)
        // path = "/{wishlistID}" или "/{wishlistID}/item/{itemID}"
        guard let wishlistID = parts.first else { return }
        let itemID: String? = (parts.count >= 3 && parts[1] == "item") ? parts[2] : nil
        Task { await resolveAndNavigate(wishlistID: wishlistID, itemID: itemID) }
    }

    /// Резолвит локальный Wishlist по push-идентификатору и программно открывает его.
    /// Push `data.wishlistID` = Firestore doc id (= sharedWishlistID для shared, либо локальный
    /// UUID для personal). Если список ещё не подтянут локально (только что присоединились) —
    /// форсим refreshWishlists и пробуем снова. Удалённый список (tombstone) не открываем.
    @MainActor
    private func resolveAndNavigate(wishlistID: String, itemID: String?) async {
        func findLocal() -> Wishlist? {
            allWishlists.first { $0.sharedWishlistID == wishlistID }
                ?? allWishlists.first { $0.id.uuidString == wishlistID }
        }
        var target = findLocal()
        if target == nil {
            // force=true — обходим 30с-throttle: свежеприсоединённый список иначе не подтянется
            // и push не откроется до следующего polling-тика.
            await services.data?.refreshWishlists(force: true)
            target = findLocal()
        }
        guard let wl = target, !wl.isTombstoned else { return }
        deeplinkItemID = itemID
        deeplinkWishlist = wl
    }
}
