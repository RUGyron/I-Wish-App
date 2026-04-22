//
//  IWishApp.swift
//  IWish
//
//  Created by Владислав Пивош on 14.04.2026.
//

import SwiftUI
import SwiftData
import CloudKit

// MARK: - AppDelegate (Remote Notifications)

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        if let queryNotif = notification as? CKQueryNotification {
            let recordType = queryNotif.subscriptionID ?? ""
            let wishlistID = queryNotif.recordFields?["wishlistID"] as? String ?? ""
            NotificationCenter.default.post(
                name: .sharedWishlistDidChange,
                object: nil,
                userInfo: ["recordType": recordType, "wishlistID": wishlistID]
            )
        }
        return .newData
    }
}

// MARK: - App

@main
struct IWishApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    let container: ModelContainer
    @State private var pendingShareURL: String?
    @State private var showingJoinFromLink = false

    init() {
        self.container = ModelContainerFactory.makeProductionContainer()
        configureAppearance()
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
