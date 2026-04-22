import SwiftUI
import SwiftData
import QRCode
import AuthenticationServices

struct ShareWishlistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.toast) private var toast
    @Query private var settingsList: [AppSettings]

    let wishlist: Wishlist

    @State private var shareManager = ShareManager()
    @State private var selectedRole: ShareRole = .editor
    @State private var selectedTTL: InviteTTL = .minutes15
    @State private var showingShareSheet = false
    @State private var showingAppleSignIn = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Wishlist name hero
                    VStack(spacing: 4) {
                        if let emoji = wishlist.coverEmoji, !emoji.isEmpty {
                            Text(emoji).font(.system(size: 44))
                        }
                        Text(wishlist.name)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text("Приглашение в список")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    // QR Code
                    qrSection

                    // Expiry
                    expiryLabel

                    // Error shown via toast

                    // Pickers
                    VStack(spacing: 16) {
                        rolePicker
                        ttlPicker
                    }
                    .padding(.horizontal)

                    // Action buttons
                    actionButtons
                        .padding(.horizontal)

                    // Revoke
                    revokeButton
                }
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Theme.background)
            .navigationTitle("Поделиться")
            .navigationBarTitleDisplayMode(.inline)
            .fontDesign(.rounded)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .onAppear {
                if let settings = settingsList.first {
                    selectedTTL = settings.defaultInviteTTL
                }
                Task {
                    guard await services.auth.ensureAuth() else {
                        toast.error("Не удалось авторизоваться")
                        return
                    }
                    // Require Sign in with Apple before sharing
                    if !services.auth.isAuthenticated {
                        showingAppleSignIn = true
                        return
                    }
                    await shareManager.generateShare(
                        for: wishlist,
                        role: selectedRole,
                        ttl: selectedTTL,
                        ownerUID: services.auth.uid ?? "",
                        ownerName: services.auth.userName ?? "Вы"
                    )
                }
            }
            .onChange(of: selectedRole) { _, _ in
                Task {
                    await shareManager.generateShare(
                        for: wishlist,
                        role: selectedRole,
                        ttl: selectedTTL,
                        ownerUID: services.auth.uid ?? "",
                        ownerName: services.auth.userName ?? "Вы"
                    )
                }
            }
            .onChange(of: selectedTTL) { _, _ in
                Task {
                    await shareManager.generateShare(
                        for: wishlist,
                        role: selectedRole,
                        ttl: selectedTTL,
                        ownerUID: services.auth.uid ?? "",
                        ownerName: services.auth.userName ?? "Вы"
                    )
                }
            }
            .onChange(of: shareManager.error) { _, newError in
                if let msg = newError { toast.error(msg) }
            }
        }
        .applyTheme()
        .sheet(isPresented: $showingAppleSignIn) {
            SignInWithAppleSheet { result in
                showingAppleSignIn = false
                Task {
                    do {
                        try await services.auth.handleSignInWithApple(result: result)
                        // Now generate share with real identity
                        await shareManager.generateShare(
                            for: wishlist,
                            role: selectedRole,
                            ttl: selectedTTL,
                            ownerUID: services.auth.uid ?? "",
                            ownerName: services.auth.userName ?? "Вы"
                        )
                    } catch {
                        toast.error("Не удалось войти через Apple")
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - QR

    private var qrSection: some View {
        Group {
            if let url = shareManager.shareURL,
               let qrImage = generateQRCode(from: url.absoluteString) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.quaternary)
                    .frame(width: 240, height: 240)
                    .overlay {
                        ProgressView()
                    }
            }
        }
    }

    private var expiryLabel: some View {
        Group {
            if let expiresAt = shareManager.expiresAt {
                Label(
                    "Действует до \(expiresAt.formatted(.dateTime.hour().minute()))",
                    systemImage: "clock"
                )
            } else {
                Label("Без ограничения по времени", systemImage: "infinity")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    // MARK: - Pickers

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Роль")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Роль", selection: $selectedRole) {
                ForEach(ShareRole.allCases) { role in
                    Text(role.label).tag(role)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var ttlPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Срок действия")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("TTL", selection: $selectedTTL) {
                ForEach(InviteTTL.allCases) { ttl in
                    Text(ttl.label).tag(ttl)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                showingShareSheet = true
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                    Text("Поделиться")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }

            Button {
                if let url = shareManager.shareURL {
                    UIPasteboard.general.string = url.absoluteString
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { copied = false }
                    }
                }
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.title3)
                        .frame(height: 22)
                    Text("Скопировать")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .sheet(isPresented: $showingShareSheet) {
            if let url = shareManager.shareURL {
                ShareSheetView(items: shareItems(for: url))
            }
        }
    }

    private var revokeButton: some View {
        Button(role: .destructive) {
            Task {
                await shareManager.revokeAll()
                dismiss()
            }
        } label: {
            Text("Отозвать все приглашения")
                .font(.caption)
        }
        .padding(.top, 16)
    }

    // MARK: - QR Generation

    private func shareItems(for url: URL) -> [Any] {
        let text = shareManager.invitationText(wishlistName: wishlist.name)
        var items: [Any] = [text]
        if let qrImage = generateQRCode(from: url.absoluteString) {
            items.append(qrImage)
        }
        return items
    }

    // MARK: - QR Generator

    // MARK: - QR Generator (Telegram blob style)

    private func generateQRCode(from string: String) -> UIImage? {
        guard let doc = try? QRCode.Document(utf8String: string, errorCorrection: .medium) else {
            return nil
        }

        // Brand color
        let brand = CGColor(srgbRed: 0.72, green: 0.38, blue: 0.06, alpha: 1)

        // Shapes — Telegram style: rounded blobs for data, smooth rounded eyes
        doc.design.shape.onPixels = QRCode.PixelShape.RoundedPath()
        doc.design.shape.eye = QRCode.EyeShape.RoundedRect()
        doc.design.shape.pupil = QRCode.PupilShape.RoundedRect()

        // Colors
        doc.design.style.onPixels = QRCode.FillStyle.Solid(brand)
        doc.design.style.eye = QRCode.FillStyle.Solid(brand)
        doc.design.style.pupil = QRCode.FillStyle.Solid(brand)
        doc.design.style.background = QRCode.FillStyle.Solid(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))

        // Logo in center (auto-masks QR pixels underneath)
        if let logo = UIImage(named: "IconPreviewLight")?.cgImage {
            doc.logoTemplate = QRCode.LogoTemplate.CircleCenter(image: logo, inset: 4)
        }

        // Render at 3x for crisp display
        return try? doc.uiImage(dimension: 840)
    }
}

// MARK: - Share Sheet

private struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Wishlist.self, Item.self, AppSettings.self,
        configurations: config
    )

    let settings = AppSettings(defaultInviteTTL: .hour1)
    container.mainContext.insert(settings)

    let wishlist = Wishlist(name: "День рождения")
    container.mainContext.insert(wishlist)
    try? container.mainContext.save()

    return ShareWishlistSheet(wishlist: wishlist)
        .modelContainer(container)
}
