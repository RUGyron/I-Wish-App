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

    private var settings: AppSettings? { settingsList.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if shareManager.isLoading {
                        loadingState
                    } else if let url = shareManager.shareURL {
                        activeShareContent(url: url)
                    } else {
                        configureShareContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
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
                if let settings {
                    selectedTTL = settings.defaultInviteTTL
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Создание ссылки...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Configure (before share created)

    private var configureShareContent: some View {
        VStack(spacing: 20) {
            // QR placeholder
            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: 200, height: 200)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 48))
                                .foregroundStyle(.tertiary)
                            Text("QR-код появится после создания")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }
            }

            rolePicker

            ttlPicker

            Button {
                shareManager.createShare(
                    for: wishlist,
                    role: selectedRole,
                    ttl: selectedTTL
                )
            } label: {
                Label("Создать ссылку", systemImage: "link.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Active Share (QR + actions)

    private func activeShareContent(url: URL) -> some View {
        VStack(spacing: 20) {
            // QR Code
            qrCodeView(for: url.absoluteString)

            // Expiry label
            if let expiresAt = shareManager.expiresAt {
                Label(
                    "Действует до \(expiresAt.formatted(.dateTime.hour().minute()))",
                    systemImage: "clock"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                Label("Без ограничения по времени", systemImage: "infinity")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            rolePicker

            ttlPicker

            // Recreate share if settings changed
            Button {
                shareManager.createShare(
                    for: wishlist,
                    role: selectedRole,
                    ttl: selectedTTL
                )
            } label: {
                Label("Обновить ссылку", systemImage: "arrow.clockwise")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.bordered)

            // Share button
            Button {
                showingShareSheet = true
            } label: {
                Label("Поделиться...", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Revoke
            Button(role: .destructive) {
                shareManager.revokeShare()
            } label: {
                Label("Отменить приглашение", systemImage: "xmark.circle")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let qrImage = generateQRCode(from: url.absoluteString) {
                ShareSheet(items: [qrImage, url])
            }
        }
    }

    // MARK: - Role Picker

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Роль")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Роль", selection: $selectedRole) {
                ForEach(ShareRole.allCases) { role in
                    Label(role.label, systemImage: role.icon).tag(role)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - TTL Picker

    private var ttlPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Срок действия")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(InviteTTL.allCases) { ttl in
                        Button {
                            selectedTTL = ttl
                        } label: {
                            Text(ttl.label)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    selectedTTL == ttl
                                        ? AnyShapeStyle(Color.accentColor)
                                        : AnyShapeStyle(.quaternary)
                                )
                                .foregroundStyle(selectedTTL == ttl ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - QR Code

    private func qrCodeView(for string: String) -> some View {
        Group {
            if let image = generateQRCode(from: string) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: 200, height: 200)
                    .overlay {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scale: CGFloat = 10
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = outputImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - iOS Share Sheet wrapper

private struct ShareSheet: UIViewControllerRepresentable {
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
