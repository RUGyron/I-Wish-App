import SwiftUI
import SwiftData
import CoreImage.CIFilterBuiltins

struct ShareWishlistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    let wishlist: Wishlist

    @State private var shareManager = ShareManager()
    @State private var selectedRole: ShareRole = .editor
    @State private var selectedTTL: InviteTTL = .minutes15
    @State private var showingShareSheet = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // QR Code
                    qrSection

                    // Expiry
                    expiryLabel

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
            .navigationTitle("Поделиться")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .onAppear {
                if let settings = settingsList.first {
                    selectedTTL = settings.defaultInviteTTL
                }
                shareManager.generateShare(for: wishlist, role: selectedRole, ttl: selectedTTL)
            }
            .onChange(of: selectedRole) { _, _ in
                shareManager.generateShare(for: wishlist, role: selectedRole, ttl: selectedTTL)
            }
            .onChange(of: selectedTTL) { _, _ in
                shareManager.generateShare(for: wishlist, role: selectedRole, ttl: selectedTTL)
            }
        }
        .applyTheme()
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
        VStack(spacing: 12) {
            // Share button
            Button {
                showingShareSheet = true
            } label: {
                Label("Поделиться", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            // Copy URL button
            Button {
                if let url = shareManager.shareURL {
                    UIPasteboard.general.string = url.absoluteString
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { copied = false }
                    }
                }
            } label: {
                Label(
                    copied ? "Скопировано" : "Скопировать ссылку",
                    systemImage: copied ? "checkmark" : "doc.on.doc"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = shareManager.shareURL {
                let text = shareManager.invitationText(wishlistName: wishlist.name)
                let qrImage = generateQRCode(from: url.absoluteString)
                let items: [Any] = [text, qrImage as Any, url].compactMap {
                    $0 is NSNull ? nil : $0
                }
                ShareSheetView(items: items.isEmpty ? [text] : items)
            }
        }
    }

    private var revokeButton: some View {
        Button(role: .destructive) {
            shareManager.revokeAll()
            dismiss()
        } label: {
            Text("Отозвать все приглашения")
                .font(.subheadline)
        }
        .padding(.top, 8)
    }

    // MARK: - QR Generation

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
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
