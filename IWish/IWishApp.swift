//
//  IWishApp.swift
//  IWish
//
//  Created by Владислав Пивош on 14.04.2026.
//

import SwiftUI
import SwiftData

@main
struct IWishApp: App {
    let container: ModelContainer

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
        guard url.scheme == "iwish",
              url.host == "join",
              let uuidString = url.pathComponents.dropFirst().first,
              let _ = UUID(uuidString: uuidString) else { return }

        NotificationCenter.default.post(
            name: .didReceiveShareLink,
            object: nil,
            userInfo: ["url": url]
        )
    }
}

extension Notification.Name {
    static let didReceiveShareLink = Notification.Name("didReceiveShareLink")
}
