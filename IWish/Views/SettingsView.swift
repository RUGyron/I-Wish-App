import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services
    @Query private var settingsList: [AppSettings]
    @State private var showingRevokeAlert = false

    private var settings: AppSettings {
        settingsList.first ?? AppSettings.loadOrCreate(in: context)
    }

    var body: some View {
        Form {
            appearanceSection
            wishesSection
            invitesSection
            privacySection
            aboutSection
        }
        .warmBackground()
        .alert("Отключить отображение имени?", isPresented: $showingRevokeAlert) {
            Button("Отмена", role: .cancel) { }
            Button("Открыть Настройки iOS") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Apple не позволяет приложениям менять это разрешение. Откройте Настройки iOS \u{2192} Apple ID \u{2192} iCloud \u{2192} Настройки приложений, чтобы отключить.")
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Иконка приложения")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    ForEach(AppIconVariant.allCases) { variant in
                        iconPreview(variant)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func iconPreview(_ variant: AppIconVariant) -> some View {
        let isSelected = settings.selectedAppIcon == variant
        return VStack(spacing: 6) {
            Image(variant.previewAsset)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.titaniumGradient, lineWidth: 0.5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
                )

            Text(variant.label)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .onTapGesture {
            appIconBinding.wrappedValue = variant
        }
    }

    private var wishesSection: some View {
        Section("Желания") {
            Picker("Валюта по умолчанию", selection: currencyBinding) {
                Text("\u{20BD}").tag("RUB")
                Text("$").tag("USD")
            }

            Toggle("Испытательный срок по умолчанию", isOn: probationEnabledBinding)

            if settings.probationEnabledByDefault {
                Picker("Длительность", selection: probationDaysBinding) {
                    ForEach(1...365, id: \.self) { day in
                        Text(String(format: NSLocalizedString("%lld дней", comment: ""), day)).tag(day)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)

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

    private var privacySection: some View {
        Section("Приватность") {
            Toggle(isOn: discoverabilityBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Показывать моё имя")
                    Text(discoverabilitySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var discoverabilityBinding: Binding<Bool> {
        Binding(
            get: { services.userProfile.discoverabilityStatus == .granted },
            set: { newValue in
                if newValue {
                    services.userProfile.requestDiscoverability()
                } else {
                    showingRevokeAlert = true
                }
            }
        )
    }

    private var discoverabilitySubtitle: String {
        switch services.userProfile.discoverabilityStatus {
        case .granted: return "Участники общих списков видят ваше имя"
        case .denied: return "Отключено — участники видят \"Вы\""
        default: return "Нужно для отображения имени участникам"
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink {
                PrivacyDisclosureView()
            } label: {
                Label("Как мы храним данные", systemImage: "lock.shield")
            }
            NavigationLink {
                MarkdownDocView(title: "Политика приватности", resourceName: "privacy")
            } label: {
                Label("Политика приватности", systemImage: "doc.text")
            }
            NavigationLink {
                MarkdownDocView(title: "Пользовательское соглашение", resourceName: "terms")
            } label: {
                Label("Пользовательское соглашение", systemImage: "doc.plaintext")
            }
        } header: {
            Text("О приложении")
        } footer: {
            Text("Версия \(appVersion)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    // MARK: - Bindings

    private var themeBinding: Binding<ThemeMode> {
        Binding(
            get: { settings.themeMode },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.35)) {
                    settings.themeMode = newValue
                }
                try? context.save()
            }
        )
    }

    private var appIconBinding: Binding<AppIconVariant> {
        Binding(
            get: { settings.selectedAppIcon },
            set: { newValue in
                settings.selectedAppIcon = newValue
                try? context.save()
                UIApplication.shared.setAlternateIconName(newValue.alternateIconName)
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
