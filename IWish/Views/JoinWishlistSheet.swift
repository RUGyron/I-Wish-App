import SwiftUI
import SwiftData
import AVFoundation
import AudioToolbox

struct JoinWishlistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.appServices) private var services
    @Environment(\.toast) private var toast
    @State private var showingScanner = false
    @State private var joinStatus: JoinStatus = .idle
    @State private var resolvedInfo: FirestoreService.ShareLinkInfo?
    @State private var showingInvitePreview = false

    var initialURL: String? = nil

    enum JoinStatus {
        case idle
        case joining
        case success(String)
        case error(String)

        var isJoining: Bool {
            if case .joining = self { return true }
            return false
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text("Присоединиться к списку")
                        .font(.title3.weight(.semibold))
                    Text("Отсканируй QR-код или вставь ссылку из буфера")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                VStack(spacing: 12) {
                    Button {
                        showingScanner = true
                    } label: {
                        Label("Сканировать QR-код", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        pasteAndJoin()
                    } label: {
                        Label("Вставить из буфера", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal)

                statusView

                Spacer()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Присоединиться")
            .navigationBarTitleDisplayMode(.inline)
            .fontDesign(.rounded)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                QRScannerView { code in
                    showingScanner = false
                    joinByLink(code)
                }
                .ignoresSafeArea(.all)
            }
        }
        .loadingOverlay(joinStatus.isJoining)
        .applyTheme()
        .onAppear {
            if let url = initialURL {
                joinByLink(url)
            }
        }
        .sheet(isPresented: $showingInvitePreview) {
            if let info = resolvedInfo {
                InvitePreviewSheet(info: info) {
                    acceptInvite()
                }
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        EmptyView()
    }

    private func pasteAndJoin() {
        guard let clipboard = UIPasteboard.general.string, !clipboard.isEmpty else {
            toast.error("Буфер обмена пуст")
            return
        }
        joinByLink(clipboard)
    }

    private func joinByLink(_ link: String) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            toast.error("Неверная ссылка")
            return
        }

        let shortID: String?
        let host = url.host() ?? ""
        let path = url.path()

        if url.scheme == "https",
           host.contains("rugyron.github.io"),
           let jRange = path.range(of: "/j/") {
            let after = path[jRange.upperBound...]
            let id = String(after.prefix(while: { $0 != "/" && $0 != "?" }))
            shortID = id.isEmpty ? nil : id
        } else if url.scheme == "iwish", host == "join" {
            shortID = url.pathComponents.last.flatMap { $0.isEmpty ? nil : $0 }
        } else {
            shortID = nil
        }

        guard let id = shortID else {
            toast.error("Неверная ссылка")
            return
        }

        joinStatus = .joining
        Task {
            do {
                guard let info = try await services.firestore.resolveInviteLink(shortID: id) else {
                    joinStatus = .idle
                    toast.error("Приглашение недействительно или истекло")
                    return
                }
                resolvedInfo = info
                joinStatus = .idle
                showingInvitePreview = true
            } catch {
                joinStatus = .idle
                toast.error("Не удалось загрузить приглашение")
            }
        }
    }

    private func acceptInvite() {
        guard let info = resolvedInfo else { return }
        Task {
            do {
                // 1. Check auth — must be signed in (not anonymous)
                guard let uid = services.auth.uid else {
                    showingInvitePreview = false
                    toast.error("Необходимо войти через Apple ID")
                    return
                }

                // 2. Join: create membership in Firestore
                try await services.firestore.joinWishlist(
                    wishlistID: info.wishlistID,
                    userUID: uid,
                    role: info.role
                )

                // 3. Fetch shared wishlist + items from Firestore
                let sharedData = try await services.firestore.fetchSharedWishlist(
                    wishlistID: info.wishlistID
                )

                // 4. Create local Wishlist + Items in SwiftData
                let wishlist = Wishlist(
                    name: sharedData.name,
                    coverEmoji: sharedData.coverEmoji,
                    ownerRecordID: sharedData.ownerUID,
                    isShared: true,
                    sharedWishlistID: info.wishlistID,
                    gradientSeed: sharedData.gradientSeed
                )
                context.insert(wishlist)

                for sharedItem in sharedData.items {
                    let item = Item(
                        name: sharedItem.name,
                        tier: ItemTier(rawValue: sharedItem.tier) ?? .maybe,
                        sortIndex: sharedItem.sortIndex,
                        currency: sharedItem.currency,
                        price: sharedItem.price,
                        url: sharedItem.url,
                        coverEmoji: sharedItem.coverEmoji
                    )
                    item.isArchived = sharedItem.isArchived
                    item.wishlist = wishlist
                    context.insert(item)
                }

                try context.save()

                showingInvitePreview = false
                toast.success("Присоединились к «\(info.wishlistName)»")
                try? await Task.sleep(for: .seconds(0.5))
                dismiss()
            } catch {
                showingInvitePreview = false
                toast.error("Не удалось присоединиться: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - QR Scanner

struct QRScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.onCodeScanned = onCodeScanned
        vc.onCancel = { dismiss() }
        return vc
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeScanned: ((String) -> Void)?
    var onCancel: (() -> Void)?

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!

    private let scanSize: CGFloat = 250
    private let scanOffsetY: CGFloat = -40

    private var torchButton: UIButton?
    private var isTorchOn = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.insetsLayoutMarginsFromSafeArea = false
        additionalSafeAreaInsets = .zero

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else {
            return
        }

        captureSession.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        captureSession.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
        metadataOutput.metadataObjectTypes = [.qr]

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        // -- Viewfinder overlay --

        let scanRect = CGRect(
            x: (view.bounds.width - scanSize) / 2,
            y: (view.bounds.height - scanSize) / 2 + scanOffsetY,
            width: scanSize,
            height: scanSize
        )

        // Dark overlay with cutout
        let overlayPath = UIBezierPath(rect: view.bounds)
        let cutoutPath = UIBezierPath(roundedRect: scanRect, cornerRadius: 24)
        overlayPath.append(cutoutPath)
        overlayPath.usesEvenOddFillRule = true

        let maskLayer = CAShapeLayer()
        maskLayer.path = overlayPath.cgPath
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = UIColor.black.withAlphaComponent(0.5).cgColor
        view.layer.addSublayer(maskLayer)

        // Smooth rounded rectangle border (Telegram style)
        let borderLayer = CAShapeLayer()
        borderLayer.path = UIBezierPath(roundedRect: scanRect, cornerRadius: 24).cgPath
        borderLayer.strokeColor = UIColor.white.cgColor
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.lineWidth = 3
        view.layer.addSublayer(borderLayer)

        // Title label above cutout
        let titleLabel = UILabel()
        titleLabel.text = "Сканируй QR-код"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: view.topAnchor, constant: scanRect.minY - 30)
        ])

        // Close button (top-left, icon style)
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        closeButton.layer.cornerRadius = 20
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),
        ])

        // Flashlight button below viewfinder
        let torch = UIButton(type: .system)
        torch.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
        torch.tintColor = .white
        torch.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        torch.layer.cornerRadius = 28
        torch.addTarget(self, action: #selector(toggleTorch), for: .touchUpInside)
        torch.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(torch)
        NSLayoutConstraint.activate([
            torch.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            torch.topAnchor.constraint(equalTo: view.centerYAnchor, constant: scanSize / 2 + scanOffsetY + 40),
            torch.widthAnchor.constraint(equalToConstant: 56),
            torch.heightAnchor.constraint(equalToConstant: 56),
        ])
        torchButton = torch

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isTorchOn {
            if let device = AVCaptureDevice.default(for: .video), device.hasTorch {
                try? device.lockForConfiguration()
                device.torchMode = .off
                device.unlockForConfiguration()
            }
        }
    }

    @objc private func closeTapped() {
        captureSession.stopRunning()
        onCancel?()
    }

    @objc private func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            isTorchOn.toggle()
            device.torchMode = isTorchOn ? .on : .off
            device.unlockForConfiguration()
            let iconName = isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill"
            torchButton?.setImage(UIImage(systemName: iconName), for: .normal)
        } catch {
            print("Torch error: \(error)")
        }
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                    didOutput metadataObjects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              metadataObject.type == .qr,
              let stringValue = metadataObject.stringValue else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.captureSession.stopRunning()
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            self.onCodeScanned?(stringValue)
        }
    }
}
