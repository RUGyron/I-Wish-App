import Foundation
import SwiftData

@Model
final class AppSettings {
    /// Singleton — всегда один instance в БД. Инвариант поддерживается
    /// `loadOrCreate(in:)`, а не schema constraint (CloudKit mirror
    /// не поддерживает `@Attribute(.unique)`).
    var id: UUID
    var themeModeRaw: String
    var defaultCurrency: String
    var hasCompletedOnboarding: Bool

    var themeMode: ThemeMode {
        get { ThemeMode(rawValue: themeModeRaw) ?? .system }
        set { themeModeRaw = newValue.rawValue }
    }

    init(
        themeMode: ThemeMode = .system,
        defaultCurrency: String = "RUB",
        hasCompletedOnboarding: Bool = false
    ) {
        self.id = UUID()
        self.themeModeRaw = themeMode.rawValue
        self.defaultCurrency = defaultCurrency
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    /// Загружает существующие или создаёт новые settings. Гарантирует ровно один instance.
    static func loadOrCreate(in context: ModelContext) -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let fresh = AppSettings()
        context.insert(fresh)
        try? context.save()
        return fresh
    }
}
