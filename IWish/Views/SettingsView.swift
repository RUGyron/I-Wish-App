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
    @State private var showingDeleteConfirm = false
    @State private var showingDeleteSheet = false
    private var settings: AppSettings {
        settingsList.first ?? AppSettings.loadOrCreate(in: context)
    }

    var body: some View {
        Form {
            accountSection
            appearanceSection
            notificationsSection
            parsingSection
            wishesSection
            invitesSection
            #if DEBUG
            debugSection
            #endif
            aboutSection
        }
        .sheet(isPresented: $showingAppleSignIn) {
            SignInWithAppleSheet { result in
                showingAppleSignIn = false
                Task {
                    do {
                        try await services.auth.handleSignInWithApple(result: result)
                        toast.success(String(format: String(localized: "Signed in as %@"), services.auth.userName ?? String(localized: "user")))
                    } catch {
                        toast.error(String(localized: "Couldn’t sign in"))
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingDeleteSheet) {
            DeleteAccountSheet { result in
                switch result {
                case .success:
                    toast.success(String(localized: "Account deleted"))
                    dismiss()
                case .failure:
                    // Сообщение об ошибке покажет сам sheet — здесь молчим.
                    break
                }
            }
            .presentationDetents([.large])
        }
        .alert("Delete account?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                showingDeleteSheet = true
            }
        } message: {
            Text("All your lists, memberships, and encryption keys will be deleted permanently. This action can’t be undone.")
        }
        .warmBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
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
                        Text("Signed in with Apple")
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
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete account", systemImage: "trash")
                        .foregroundStyle(.red)
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
                            Text("Sign in with Apple")
                                .font(.body.weight(.medium))
                            Text("Required to share lists")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Account")
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: themeBinding) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("App icon")
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

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Update notifications", isOn: pushEnabledBinding)
            if settings.pushNotificationsEnabled {
                Toggle("On by default for new lists", isOn: pushDefaultBinding)
                if services.push.authorizationStatus == .denied {
                    Text("System notifications are disabled. Enable them in iOS Settings → I Wish.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if services.push.authorizationStatus == .notDetermined {
                    Button {
                        Task {
                            _ = await services.push.requestAuthorization()
                        }
                    } label: {
                        Text("Allow notifications")
                    }
                }
            }
        }
    }

    private var pushEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.pushNotificationsEnabled },
            set: { newValue in
                settings.pushNotificationsEnabled = newValue
                try? context.save()
                // Доводим глобальный тоггл до Firestore (users/{uid}.pushEnabled) — CF фильтрует по нему.
                services.push.syncPushEnabledPreference(newValue)
                if newValue && services.push.authorizationStatus == .notDetermined {
                    Task { _ = await services.push.requestAuthorization() }
                }
            }
        )
    }

    private var pushDefaultBinding: Binding<Bool> {
        Binding(
            get: { settings.newWishlistNotificationsDefault },
            set: { newValue in
                settings.newWishlistNotificationsDefault = newValue
                try? context.save()
            }
        )
    }

    // MARK: - Parsing

    private var parsingSection: some View {
        Section {
            Picker("Mode", selection: parseFillModeBinding) {
                ForEach(ParseFillMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            if settings.parseFillMode != .off {
                Toggle("Title", isOn: parseBinding(\.parseFillTitle))
                Toggle("Price", isOn: parseBinding(\.parseFillPrice))
                Toggle("Cover", isOn: parseBinding(\.parseFillImage))
                Toggle("Description", isOn: parseBinding(\.parseFillDescription))
            }
        } header: {
            Text("Link parsing")
        } footer: {
            Text("“Don’t fill” — leaves everything as is. “Only empty fields” — fills a field only if you haven’t typed anything. “Always overwrite” — replaces with data from the page.")
        }
    }

    private var parseFillModeBinding: Binding<ParseFillMode> {
        Binding(
            get: { settings.parseFillMode },
            set: { newValue in
                settings.parseFillMode = newValue
                try? context.save()
            }
        )
    }

    private func parseBinding(_ key: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: key] },
            set: { newValue in
                settings[keyPath: key] = newValue
                try? context.save()
            }
        )
    }

    private var wishesSection: some View {
        Section("Wishes") {
            Picker("Default currency", selection: currencyBinding) {
                Text(verbatim: "\u{20BD}").tag("RUB")
                Text(verbatim: "$").tag("USD")
            }

            Toggle("Probation period by default", isOn: probationEnabledBinding)

            if settings.probationEnabledByDefault {
                Picker("Duration", selection: probationDaysBinding) {
                    ForEach(1...365, id: \.self) { day in
                        Text(String(format: NSLocalizedString("%lld дней", comment: ""), day)).tag(day)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)

                Toggle("Notify when period ends", isOn: notifyProbationBinding)
            }
        }
    }

    private var invitesSection: some View {
        Section("Invitations") {
            Picker("Default role", selection: shareRoleBinding) {
                ForEach(ShareRole.allCases) { role in
                    Text(role.label).tag(role)
                }
            }
            Picker("Default expiry", selection: inviteTTLBinding) {
                ForEach(InviteTTL.allCases) { ttl in
                    Text(ttl.label).tag(ttl)
                }
            }
        }
    }

    #if DEBUG
    @State private var isSeeding = false
    private var debugSection: some View {
        Section("Debug") {
            Button {
                isSeeding = true
                Task {
                    await services.data?.seedMockDataForScreenshots()
                    isSeeding = false
                    toast.success(String(localized: "Test data created"))
                }
            } label: {
                Label("Seed test data", systemImage: "wand.and.stars")
            }
            .disabled(isSeeding)
            Button(role: .destructive) {
                services.data?.wipeAllLocal()
                toast.success(String(localized: "Local data wiped"))
            } label: {
                Label("Wipe local data", systemImage: "trash")
            }
        }
    }
    #endif

    private var aboutSection: some View {
        Section {
            NavigationLink {
                PrivacyDisclosureView()
            } label: {
                Label("How we store your data", systemImage: "lock.shield")
            }
            NavigationLink {
                MarkdownDocView(title: String(localized: "Privacy Policy"), resourceName: "privacy")
            } label: {
                Label("Privacy Policy", systemImage: "doc.text")
            }
            NavigationLink {
                MarkdownDocView(title: String(localized: "Terms of Use"), resourceName: "terms")
            } label: {
                Label("Terms of Use", systemImage: "doc.plaintext")
            }
            Button {
                openFeedbackMail()
            } label: {
                Label("Feedback", systemImage: "envelope")
            }
            Button {
                ReviewService.openAppStoreReview()
            } label: {
                Label("Rate the app", systemImage: "star.fill")
                    .foregroundStyle(.yellow)
            }
        } header: {
            Text("About")
        } footer: {
            Text("Version \(appVersion)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
        }
    }

    // MARK: - Sign Out


    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
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
        let subject = String(localized: "I Wish — feedback")
        let body = String(format: String(localized: "\n\n\n———\nVersion: %@ (%@)\niOS: %@"), version, build, UIDevice.current.systemVersion)
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
