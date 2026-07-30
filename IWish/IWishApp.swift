//
//  IWishApp.swift
//  IWish
//
//  Created by Владислав Пивош on 14.04.2026.
//

import SwiftUI
import SwiftData
import FirebaseCore

// MARK: - App

@main
struct IWishApp: App {
    @UIApplicationDelegateAdaptor(IWishAppDelegate.self) var appDelegate
    let container: ModelContainer
    @State private var pendingShareURL: String?
    @State private var showingJoinFromLink = false

    init() {
        FirebaseApp.configure()
        self.container = ModelContainerFactory.makeProductionContainer()
        configureAppearance()
        preheatKeyboard()
        KeyboardDismissInstaller.installIfNeeded()
    }

    private func configureAppearance() {
        let seg = UISegmentedControl.appearance()
        seg.setContentHuggingPriority(.defaultLow, for: .vertical)
        // Increase segmented control height via font size
        seg.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 15, weight: .medium)], for: .normal)
        seg.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 15, weight: .semibold)], for: .selected)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appServices, .shared)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .sheet(isPresented: $showingJoinFromLink) {
                    JoinWishlistSheet(initialURL: pendingShareURL)
                }
                .task {
                    // One-time: ключи существующих списков → shared keychain group для NSE.
                    AppServices.shared.data?.migrateSharedKeychainIfNeeded()
                    // v1.1 one-time migration backfill — гонится в фоне, не блокирует UI.
                    // updateItem использует preserve-unknown-keys → не теряет ничего.
                    await AppServices.shared.data?.runV11BackfillIfNeeded()
                }
        }
        .modelContainer(container)
    }

    private func preheatKeyboard() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows.first else { return }
            let tf = UITextField(frame: CGRect(x: -100, y: -100, width: 1, height: 1))
            tf.isHidden = true
            window.addSubview(tf)
            tf.becomeFirstResponder()
            DispatchQueue.main.async {
                tf.resignFirstResponder()
                tf.removeFromSuperview()
            }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        // Universal Link: https://rugyron.github.io/I-Wish-App/j/{shortID}
        if url.scheme == "https",
           (url.host() ?? "").contains("rugyron.github.io"),
           url.path().contains("/j/") {
            pendingShareURL = url.absoluteString
            showingJoinFromLink = true
            return
        }

        // Custom scheme: iwish://join/{shortID}
        if url.scheme == "iwish", url.host() == "join" {
            pendingShareURL = url.absoluteString
            showingJoinFromLink = true
            return
        }

        // Push deeplink: iwish://wishlist/{id} или iwish://wishlist/{id}/item/{itemID}.
        // Парсится в RootView.handlePushDeeplink через NotificationCenter.
        if url.scheme == "iwish", url.host() == "wishlist" {
            NotificationCenter.default.post(name: .iwishPushDeeplink, object: url)
            return
        }
    }
}

extension Notification.Name {
    /// Запрос навигации к конкретному вишлисту/желанию из push-уведомления.
    /// object = URL вида iwish://wishlist/{id} либо iwish://wishlist/{id}/item/{itemID}.
    static let iwishPushDeeplink = Notification.Name("iwishPushDeeplink")
}

extension Notification.Name {
    static let didReceiveShareLink = Notification.Name("didReceiveShareLink")
    static let sharedWishlistDidChange = Notification.Name("sharedWishlistDidChange")
}
