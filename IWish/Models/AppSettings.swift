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

    // Probation defaults
    var probationEnabledByDefault: Bool = false
    var defaultProbationDuration: Double = 2_592_000 // 30 дней в секундах
    var notifyOnProbationEnd: Bool = false

    // Invite defaults
    var defaultInviteTTLRaw: String = "15m"

    // App icon
    var selectedAppIconRaw: String = "auto"

    // MARK: - Computed bridges

    var themeMode: ThemeMode {
        get { ThemeMode(rawValue: themeModeRaw) ?? .system }
        set { themeModeRaw = newValue.rawValue }
    }

    var defaultInviteTTL: InviteTTL {
        get { InviteTTL(rawValue: defaultInviteTTLRaw) ?? .minutes15 }
        set { defaultInviteTTLRaw = newValue.rawValue }
    }

    var selectedAppIcon: AppIconVariant {
        get { AppIconVariant(rawValue: selectedAppIconRaw) ?? .auto }
        set { selectedAppIconRaw = newValue.rawValue }
    }

    /// Длительность испытательного срока в днях (для UI).
    var probationDurationDays: Int {
        get { max(1, Int(defaultProbationDuration / 86400)) }
        set { defaultProbationDuration = Double(newValue) * 86400 }
    }

    init(
        themeMode: ThemeMode = .system,
        defaultCurrency: String = "RUB",
        hasCompletedOnboarding: Bool = false,
        probationEnabledByDefault: Bool = false,
        defaultProbationDuration: Double = 30 * 86400,
        notifyOnProbationEnd: Bool = false,
        defaultInviteTTL: InviteTTL = .minutes15,
        selectedAppIcon: AppIconVariant = .auto
    ) {
        self.id = UUID()
        self.themeModeRaw = themeMode.rawValue
        self.defaultCurrency = defaultCurrency
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.probationEnabledByDefault = probationEnabledByDefault
        self.defaultProbationDuration = defaultProbationDuration
        self.notifyOnProbationEnd = notifyOnProbationEnd
        self.defaultInviteTTLRaw = defaultInviteTTL.rawValue
        self.selectedAppIconRaw = selectedAppIcon.rawValue
    }

    /// Загружает существующие или создаёт новые settings. Гарантирует ровно один instance.
    static func loadOrCreate(in context: ModelContext) -> AppSettings {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let fresh = AppSettings()
        context.insert(fresh)
        try? context.save()
        return fresh
    }
}
