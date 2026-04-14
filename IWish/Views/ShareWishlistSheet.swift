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
            .background(Theme.background)
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
                ShareSheetView(items: shareItems(for: url))
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

    private func shareItems(for url: URL) -> [Any] {
        let text = shareManager.invitationText(wishlistName: wishlist.name)
        var items: [Any] = [text]
        if let qrImage = generateQRCode(from: url.absoluteString) {
            items.append(qrImage)
        }
        return items
    }

    // MARK: - Styled QR Generator

    private func generateQRCode(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "H"

        guard let ciImage = filter.outputImage else { return nil }

        let n = Int(ciImage.extent.width)
        let matrix = qrMatrix(from: ciImage, size: n)

        let canvasSize: CGFloat = 840
        let padding: CGFloat = canvasSize * 0.04
        let qrArea = canvasSize - padding * 2
        let mod = qrArea / CGFloat(n)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvasSize, height: canvasSize))
        return renderer.image { ctx in
            let gc = ctx.cgContext

            // White rounded background
            let bgRect = CGRect(origin: .zero, size: CGSize(width: canvasSize, height: canvasSize))
            UIBezierPath(roundedRect: bgRect, cornerRadius: canvasSize * 0.06).addClip()
            UIColor.white.setFill()
            ctx.fill(bgRect)

            // Draw QR modules in black first, then gradient mask
            // Colored QR modules with gradient
            UIColor.white.setFill()
            UIBezierPath(roundedRect: bgRect, cornerRadius: canvasSize * 0.06).fill()

            gc.translateBy(x: padding, y: padding)

            // Gradient colors for modules
            let amberTop = UIColor(red: 0.85, green: 0.52, blue: 0.12, alpha: 1)
            let amberBottom = UIColor(red: 0.62, green: 0.32, blue: 0.08, alpha: 1)

            for row in 0..<n {
                let t = CGFloat(row) / CGFloat(n)
                let r = amberTop.cgColor.components![0] * (1 - t) + amberBottom.cgColor.components![0] * t
                let g = amberTop.cgColor.components![1] * (1 - t) + amberBottom.cgColor.components![1] * t
                let b = amberTop.cgColor.components![2] * (1 - t) + amberBottom.cgColor.components![2] * t
                UIColor(red: r, green: g, blue: b, alpha: 1).setFill()

                for col in 0..<n {
                    guard matrix[row][col] else { continue }

                    // Logo zone — skip center
                    let centerZone = CGFloat(n) * 0.35
                    let half = CGFloat(n) / 2
                    if CGFloat(row) > half - centerZone/2 && CGFloat(row) < half + centerZone/2 &&
                       CGFloat(col) > half - centerZone/2 && CGFloat(col) < half + centerZone/2 {
                        continue
                    }

                    if isFinderZone(row: row, col: col, n: n) {
                        continue
                    }

                    let cx = CGFloat(col) * mod + mod / 2
                    let cy = CGFloat(row) * mod + mod / 2
                    let dotR = mod * 0.40

                    let hasRight = col + 1 < n && matrix[row][col + 1] && !isFinderZone(row: row, col: col + 1, n: n)
                    let hasBottom = row + 1 < n && matrix[row + 1][col] && !isFinderZone(row: row + 1, col: col, n: n)

                    if hasRight {
                        let rect = CGRect(x: cx - dotR, y: cy - dotR, width: mod + dotR, height: dotR * 2)
                        UIBezierPath(roundedRect: rect, cornerRadius: dotR * 0.6).fill()
                    } else if hasBottom {
                        let rect = CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: mod + dotR)
                        UIBezierPath(roundedRect: rect, cornerRadius: dotR * 0.6).fill()
                    } else {
                        let dotRect = CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)
                        UIBezierPath(roundedRect: dotRect, cornerRadius: dotR * 0.6).fill()
                    }
                }
            }

            // Finder patterns with gradient
            drawStyledFinder(gc: gc, x: 0, y: 0, mod: mod, color: amberTop)
            drawStyledFinder(gc: gc, x: CGFloat(n - 7) * mod, y: 0, mod: mod, color: amberTop.blend(with: amberBottom, ratio: 0.3))
            drawStyledFinder(gc: gc, x: 0, y: CGFloat(n - 7) * mod, mod: mod, color: amberBottom.blend(with: amberTop, ratio: 0.3))

            gc.translateBy(x: -padding, y: -padding)

            // Logo in center
            if let logo = UIImage(named: "IconPreviewLight") {
                let logoSize = canvasSize * 0.20
                let logoRect = CGRect(
                    x: (canvasSize - logoSize) / 2,
                    y: (canvasSize - logoSize) / 2,
                    width: logoSize, height: logoSize
                )
                let bgPad: CGFloat = 10
                let bgLogoRect = logoRect.insetBy(dx: -bgPad, dy: -bgPad)
                UIColor.white.setFill()
                UIBezierPath(roundedRect: bgLogoRect, cornerRadius: bgLogoRect.width * 0.22).fill()
                logo.draw(in: logoRect)
            }
        }
    }

    private func qrMatrix(from ciImage: CIImage, size n: Int) -> [[Bool]] {
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent),
              let provider = cgImage.dataProvider,
              let data = provider.data,
              let ptr = CFDataGetBytePtr(data) else {
            return Array(repeating: Array(repeating: false, count: n), count: n)
        }
        let bpr = cgImage.bytesPerRow
        var matrix = Array(repeating: Array(repeating: false, count: n), count: n)
        for row in 0..<n {
            for col in 0..<n {
                matrix[row][col] = ptr[row * bpr + col * 4] == 0
            }
        }
        return matrix
    }

    private func isFinderZone(row: Int, col: Int, n: Int) -> Bool {
        let inTL = row < 8 && col < 8
        let inTR = row < 8 && col >= n - 8
        let inBL = row >= n - 8 && col < 8
        return inTL || inTR || inBL
    }

    private func drawStyledFinder(gc: CGContext, x: CGFloat, y: CGFloat, mod: CGFloat, color: UIColor) {
        let outerSize = 7 * mod
        let outerRect = CGRect(x: x, y: y, width: outerSize, height: outerSize)
        let outerRadius = mod * 1.8

        // Outer ring
        color.setFill()
        UIBezierPath(roundedRect: outerRect, cornerRadius: outerRadius).fill()

        // White gap
        let gap = mod * 0.9
        let innerRect = outerRect.insetBy(dx: gap, dy: gap)
        UIColor.white.setFill()
        UIBezierPath(roundedRect: innerRect, cornerRadius: outerRadius * 0.7).fill()

        // Inner filled square
        let centerGap = mod * 1.8
        let centerRect = outerRect.insetBy(dx: centerGap, dy: centerGap)
        color.setFill()
        UIBezierPath(roundedRect: centerRect, cornerRadius: outerRadius * 0.45).fill()
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

// MARK: - UIColor Blend

private extension UIColor {
    func blend(with other: UIColor, ratio: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * ratio,
            green: g1 + (g2 - g1) * ratio,
            blue: b1 + (b2 - b1) * ratio,
            alpha: 1
        )
    }
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
