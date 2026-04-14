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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .background(KeyboardPreheater())
        }
        .modelContainer(container)
    }
}

// MARK: - Keyboard Preheater

private struct KeyboardPreheater: UIViewRepresentable {
    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.alpha = 0
        tf.isUserInteractionEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            tf.becomeFirstResponder()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                tf.resignFirstResponder()
            }
        }
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {}
}
