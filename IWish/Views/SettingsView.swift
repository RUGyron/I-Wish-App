import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    private var settings: AppSettings {
        settingsList.first ?? AppSettings.loadOrCreate(in: context)
    }

    var body: some View {
        Form {
            appearanceSection
            wishesSection
            invitesSection
            aboutSection
        }
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { dismiss() }
            }
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        Section("Внешний вид") {
            Picker("Тема", selection: themeBinding) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            // TODO: Actual icon switching via UIApplication.shared.setAlternateIconName
            // is deferred to a later phase. For now we only persist the preference.
            Picker("Иконка приложения", selection: appIconBinding) {
                ForEach(AppIconVariant.allCases) { variant in
                    Text(variant.label).tag(variant)
                }
            }
        }
    }

    private var wishesSection: some View {
        Section("Желания") {
            Picker("Валюта по умолчанию", selection: currencyBinding) {
                Text("\u{20BD} Рубль").tag("RUB")
                Text("$ Доллар").tag("USD")
            }

            Toggle("Испытательный срок по умолчанию", isOn: probationEnabledBinding)

            if settings.probationEnabledByDefault {
                Stepper(
                    "\(settings.probationDurationDays) \(daysDeclension(settings.probationDurationDays))",
                    value: probationDaysBinding,
                    in: 1...365
                )

                Toggle("Уведомлять о конце срока", isOn: notifyProbationBinding)
            }
        }
    }

    private var invitesSection: some View {
        Section("Приглашения") {
            Picker("Срок действия по умолчанию", selection: inviteTTLBinding) {
                ForEach(InviteTTL.allCases) { ttl in
                    Text(ttl.label).tag(ttl)
                }
            }
        }
    }

    private var aboutSection: some View {
        Section("О приложении") {
            LabeledContent("Версия", value: appVersion)
            Text("Политика приватности")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    /// Russian declension for "день/дня/дней".
    private func daysDeclension(_ n: Int) -> String {
        let mod100 = n % 100
        let mod10 = n % 10
        if mod100 >= 11 && mod100 <= 19 { return "дней" }
        switch mod10 {
        case 1:    return "день"
        case 2, 3, 4: return "дня"
        default:   return "дней"
        }
    }

    // MARK: - Bindings

    private var themeBinding: Binding<ThemeMode> {
        Binding(
            get: { settings.themeMode },
            set: {
                settings.themeMode = $0
                try? context.save()
            }
        )
    }

    private var appIconBinding: Binding<AppIconVariant> {
        Binding(
            get: { settings.selectedAppIcon },
            set: {
                settings.selectedAppIcon = $0
                try? context.save()
            }
        )
    }

    private var currencyBinding: Binding<String> {
        Binding(
            get: { settings.defaultCurrency },
            set: {
                settings.defaultCurrency = $0
                try? context.save()
            }
        )
    }

    private var probationEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.probationEnabledByDefault },
            set: {
                settings.probationEnabledByDefault = $0
                try? context.save()
            }
        )
    }

    private var probationDaysBinding: Binding<Int> {
        Binding(
            get: { settings.probationDurationDays },
            set: {
                settings.probationDurationDays = $0
                try? context.save()
            }
        )
    }

    private var notifyProbationBinding: Binding<Bool> {
        Binding(
            get: { settings.notifyOnProbationEnd },
            set: { newValue in
                settings.notifyOnProbationEnd = newValue
                try? context.save()
                if newValue {
                    requestNotificationPermission()
                }
            }
        )
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if !granted {
                Task { @MainActor in
                    settings.notifyOnProbationEnd = false
                    try? context.save()
                }
            }
        }
    }

    private var inviteTTLBinding: Binding<InviteTTL> {
        Binding(
            get: { settings.defaultInviteTTL },
            set: {
                settings.defaultInviteTTL = $0
                try? context.save()
            }
        )
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .modelContainer(for: [Wishlist.self, Item.self, AppSettings.self], inMemory: true)
    }
}
