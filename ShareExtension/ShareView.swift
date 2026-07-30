import SwiftUI

/// Share Extension UI: при открытии сразу делает parse + Gemini refine (если HTML / API доступны).
/// Юзер видит автозаполненные title/price/description/image, может поправить, выбрать важность
/// и список → "Добавить".
struct ShareView: View {
    let url: URL
    let sharedTitle: String?
    let imageData: Data?
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var name: String = ""
    @State private var descriptionText: String = ""
    @State private var priceText: String = ""
    @State private var currency: String = "RUB"
    @State private var tierRaw: String = "maybe"
    @State private var selectedWishlistID: String?
    @State private var wishlists: [SharedStorage.WishlistSummary] = []
    @State private var noWishlists: Bool = false
    @State private var fetchedImageData: Data?
    @State private var isFetching: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                nameSection
                priceSection
                descriptionSection
                tierSection
                wishlistSection
            }
            .navigationTitle("New wish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(canSave == false)
                }
            }
            .onAppear { onAppearInit() }
            .task { await fetchMetadata() }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var previewSection: some View {
        Section {
            HStack(spacing: 12) {
                let image = fetchedImageData ?? imageData
                if let data = image, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.tertiary)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Group {
                                if isFetching {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "link").foregroundStyle(.secondary)
                                }
                            }
                        )
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isFetching {
                        Text("Parsing…")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var nameSection: some View {
        Section("Name") {
            TextField("What are you adding", text: $name)
                .textInputAutocapitalization(.sentences)
        }
    }

    private var priceSection: some View {
        Section("Price") {
            HStack {
                TextField("Price", text: $priceText)
                    .keyboardType(.numberPad)
                Picker("Currency", selection: $currency) {
                    Text(verbatim: "₽").tag("RUB")
                    Text(verbatim: "$").tag("USD")
                    Text(verbatim: "€").tag("EUR")
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private var descriptionSection: some View {
        Section("Description") {
            TextField("Optional", text: $descriptionText, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    private var tierSection: some View {
        Section("Importance") {
            Picker("Importance", selection: $tierRaw) {
                Text("🔥 Must have").tag("must")
                Text("✨ Maybe").tag("maybe")
                Text("💭 Idea").tag("idea")
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var wishlistSection: some View {
        if noWishlists {
            Section {
                Text("Create a wishlist in the app first")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section("List") {
                Picker("List", selection: $selectedWishlistID) {
                    ForEach(wishlists) { wl in
                        Label {
                            HStack {
                                Text(wl.name).lineLimit(1)
                                if wl.isShared {
                                    Image(systemName: "person.2.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        } icon: {
                            Text(wl.emoji ?? "📋")
                        }
                        .tag(Optional(wl.id))
                    }
                }
                .pickerStyle(.navigationLink)
            }
        }
    }

    private func onAppearInit() {
        if let sharedTitle, !sharedTitle.isEmpty, name.isEmpty {
            name = sharedTitle
        }
        wishlists = SharedStorage.readWishlistsCache().sorted { $0.updatedAt > $1.updatedAt }
        if wishlists.isEmpty {
            noWishlists = true
        } else if selectedWishlistID == nil {
            selectedWishlistID = wishlists.first?.id
        }
    }

    /// Auto-fetch metadata. В extension работает только **raw extractors** (WB API + OG + JSON-LD).
    /// Gemini refine происходит в main app при обработке очереди (heavier, нужен Firebase).
    /// Extension должен быть лёгким — memory limit ~16MB.
    private func fetchMetadata() async {
        isFetching = true
        let meta = await URLMetadataService.fetch(from: url)
        isFetching = false

        if name.trimmingCharacters(in: .whitespaces).isEmpty, let t = meta.title, !t.isEmpty {
            name = t
        }
        if priceText.isEmpty, let p = meta.price {
            priceText = String(Int(p.rounded()))
        }
        if let c = meta.currency, !c.isEmpty {
            currency = c
        }
        if descriptionText.trimmingCharacters(in: .whitespaces).isEmpty, let d = meta.descriptionText {
            descriptionText = d
        }
        if fetchedImageData == nil, let img = meta.image {
            fetchedImageData = compressedJPEG(img)
        }
    }

    private func compressedJPEG(_ image: UIImage) -> Data? {
        let maxEdge: CGFloat = 1024
        let size = image.size
        let largest = max(size.width, size.height)
        let scaledImage: UIImage = {
            guard largest > maxEdge else { return image }
            let scale = maxEdge / largest
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            defer { UIGraphicsEndImageContext() }
            image.draw(in: CGRect(origin: .zero, size: newSize))
            return UIGraphicsGetImageFromCurrentImageContext() ?? image
        }()
        return scaledImage.jpegData(compressionQuality: 0.7)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let priceValue = Double(priceText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: ""))
        let descTrimmed = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageToSave = fetchedImageData ?? imageData
        let share = SharedStorage.PendingShare(
            url: url.absoluteString,
            title: trimmed,
            imageData: imageToSave,
            wishlistID: selectedWishlistID,
            tierRaw: tierRaw,
            createdAt: .now,
            price: priceValue,
            currency: priceValue != nil ? currency : nil,
            descriptionText: descTrimmed.isEmpty ? nil : descTrimmed
        )
        SharedStorage.appendPendingShare(share)
        onSave()
    }
}
