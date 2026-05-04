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
    let container: ModelContainer
    @State private var pendingShareURL: String?
    @State private var showingJoinFromLink = false

    init() {
        FirebaseApp.configure()
        self.container = ModelContainerFactory.makeProductionContainer()
        configureAppearance()
        KeyboardDismissBarInstaller.install()
        preheatKeyboard()
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
    }
}

extension Notification.Name {
    static let didReceiveShareLink = Notification.Name("didReceiveShareLink")
    static let sharedWishlistDidChange = Notification.Name("sharedWishlistDidChange")
}
