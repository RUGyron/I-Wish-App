import SwiftUI
import SwiftData
import UserNotifications
import AuthenticationServices

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services
    @Environment(\.toast) private var toast
    @Query private var settingsList: [AppSettings]
    @State private var showingAppleSignIn = false
    private var settings: AppSettings {
        settingsList.first ?? AppSettings.loadOrCreate(in: context)
    }

    var body: some View {
        Form {
            accountSection
            appearanceSection
            wishesSection
            invitesSection
            aboutSection
        }
        .sheet(isPresented: $showingAppleSignIn) {
            SignInWithAppleSheet { result in
                showingAppleSignIn = false
                Task {
                    do {
                        try await services.auth.handleSignInWithApple(result: result)
                        toast.success("Вы вошли как \(services.auth.userName ?? "пользователь")")
                    } catch {
                        toast.error("Не удалось войти")
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .warmBackground()
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { dismiss() }
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section {
            if services.auth.isAuthenticated {
                HStack {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(services.auth.userName ?? "Apple ID")
                            .font(.body.weight(.medium))
                        Text("Вы вошли через Apple")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button(role: .destructive) {
                    let wishlistDescriptor = FetchDescriptor<Wishlist>()
                    if let all = try? context.fetch(wishlistDescriptor) {
                        for wl in all { context.delete(wl) }
                    }
                    let itemDescriptor = FetchDescriptor<Item>()
                    if let all = try? context.fetch(itemDescriptor) {
                        for item in all { context.delete(item) }
                    }
                    try? context.save()
                    try? services.auth.signOut()
                } label: {
                    Label("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } else {
                Button {
                    showingAppleSignIn = true
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.title2)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Войти через Apple")
                                .font(.body.weight(.medium))
                            Text("Для шеринга списков")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Аккаунт")
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
            Picker("Роль по умолчанию", selection: shareRoleBinding) {
                ForEach(ShareRole.allCases) { role in
                    Text(role.label).tag(role)
                }
            }
            Picker("Срок действия по умолчанию", selection: inviteTTLBinding) {
                ForEach(InviteTTL.allCases) { ttl in
                    Text(ttl.label).tag(ttl)
                }
            }
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
                MarkdownDocView(title: "Политика конфиденциальности", resourceName: "privacy")
            } label: {
                Label("Политика конфиденциальности", systemImage: "doc.text")
            }
            NavigationLink {
                MarkdownDocView(title: "Пользовательское соглашение", resourceName: "terms")
            } label: {
                Label("Пользовательское соглашение", systemImage: "doc.plaintext")
            }
            Button {
                openFeedbackMail()
            } label: {
                Label("Обратная связь", systemImage: "envelope")
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

    // MARK: - Sign Out


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

    private var shareRoleBinding: Binding<ShareRole> {
        Binding(
            get: { settings.defaultShareRole },
            set: {
                settings.defaultShareRole = $0
                try? context.save()
            }
        )
    }

    private func openFeedbackMail() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let subject = "I Wish — обратная связь"
        let body = "\n\n\n———\nВерсия: \(version) (\(build))\niOS: \(UIDevice.current.systemVersion)"
        guard
            let s = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let b = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "mailto:pivosh098@gmail.com?subject=\(s)&body=\(b)")
        else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .modelContainer(for: [Wishlist.self, Item.self, AppSettings.self], inMemory: true)
    }
}
