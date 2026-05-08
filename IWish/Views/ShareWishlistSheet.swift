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
    @State private var canInvite = true
    @State private var showingShareSheet = false
    @State private var showingAppleSignIn = false
    @State private var showingExportSheet = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Group {
                if shareManager.shareURL == nil {
                    // Loading state — QR not ready yet
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Генерация приглашения...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
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

                            // Pickers
                            VStack(spacing: 16) {
                                rolePicker
                                ttlPicker
                                Toggle("Участники могут приглашать", isOn: $canInvite)
                                    .tint(Color(red: 0.72, green: 0.38, blue: 0.06))
                            }
                            .padding(.horizontal)

                            // Action buttons
                            actionButtons
                                .padding(.horizontal)

                            // Export
                            exportButton
                                .padding(.horizontal)

                            // Revoke
                            revokeButton
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
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
                    selectedRole = settings.defaultShareRole
                }
                Task {
                    guard services.auth.isAuthenticated else {
                        showingAppleSignIn = true
                        return
                    }
                    await generateShareNow()
                }
            }
            .onChange(of: selectedRole) { _, _ in
                Task { await generateShareNow() }
            }
            .onChange(of: selectedTTL) { _, _ in
                Task { await generateShareNow() }
            }
            .onChange(of: canInvite) { _, _ in
                Task { await generateShareNow() }
            }
            .onChange(of: shareManager.error) { _, newError in
                if let msg = newError { toast.error(msg) }
            }
        }
        .loadingOverlay(shareManager.isLoading)
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
                            canInvite: canInvite,
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

    // MARK: - Helpers

    private func generateShareNow() async {
        // Acquire DataService lock to prevent polling during share
        await services.data?.acquireLockPublic()
        defer { services.data?.releaseLockPublic() }

        await shareManager.generateShare(
            for: wishlist,
            role: selectedRole,
            ttl: selectedTTL,
            canInvite: canInvite,
            ownerUID: services.auth.uid ?? "",
            ownerName: services.auth.userName ?? "Вы"
        )
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

    /// Permission inheritance: можно приглашать только с правами не выше своих.
    /// Owner и editor — могут пригласить editor или viewer. Viewer — только viewer.
    /// Концепция "пригласить как owner" не существует (owner единственный, ставится при создании share).
    private var availableRoles: [ShareRole] {
        let myRole = wishlist.myRole ?? "owner"  // personal wishlists owned
        if myRole == "viewer" {
            return [.viewer]
        }
        return ShareRole.allCases  // owner или editor — могут любую (.editor или .viewer)
    }

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Роль")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if availableRoles.count == 1, let only = availableRoles.first {
                    Text(only == .viewer ? "(вы зритель → можно приглашать только зрителями)" : "")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if availableRoles.count > 1 {
                Picker("Роль", selection: $selectedRole) {
                    ForEach(availableRoles) { role in
                        Text(role.label).tag(role)
                    }
                }
                .pickerStyle(.segmented)
            } else if let only = availableRoles.first {
                Text(only.label)
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .onAppear {
            // Если default из Settings выше дозволенной — clamp.
            if !availableRoles.contains(selectedRole), let firstAllowed = availableRoles.first {
                selectedRole = firstAllowed
            }
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

    private var exportButton: some View {
        Button {
            showingExportSheet = true
        } label: {
            VStack(spacing: 5) {
                Image(systemName: "doc.text")
                    .font(.title3)
                Text("Экспорт файлом")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .sheet(isPresented: $showingExportSheet) {
            let text = exportText()
            ShareSheetView(items: [text])
        }
    }

    private func exportText() -> String {
        let items = (wishlist.items ?? []).filter { !$0.isArchived }
        var lines = ["📝 \(wishlist.name)", ""]
        for (i, item) in items.enumerated() {
            var line = "\(i + 1). \(item.tier.emoji) \(item.name)"
            if let price = item.price {
                let fmt = NumberFormatter()
                fmt.numberStyle = .currency
                fmt.currencyCode = item.currency
                fmt.maximumFractionDigits = 0
                if let priceStr = fmt.string(from: NSNumber(value: price)) {
                    line += " — \(priceStr)"
                }
            }
            if let url = item.url, !url.isEmpty {
                line += "\n   🔗 \(url)"
            }
            lines.append(line)
        }
        if items.isEmpty {
            lines.append("Список пуст")
        }
        return lines.joined(separator: "\n")
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
