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
        }
        .modelContainer(container)
    }
}
