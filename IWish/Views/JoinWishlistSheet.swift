import SwiftUI
import AVFoundation
import AudioToolbox

struct JoinWishlistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingScanner = false
    @State private var joinStatus: JoinStatus = .idle

    enum JoinStatus {
        case idle
        case joining
        case success(String)
        case error(String)
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
        .applyTheme()
    }

    @ViewBuilder
    private var statusView: some View {
        switch joinStatus {
        case .idle:
            EmptyView()
        case .joining:
            ProgressView("Подключение...")
                .padding()
        case .success(let name):
            Label("Присоединились к \u{00AB}\(name)\u{00BB}", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .padding()
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
                .padding()
        }
    }

    private func pasteAndJoin() {
        guard let clipboard = UIPasteboard.general.string, !clipboard.isEmpty else {
            joinStatus = .error("Буфер обмена пуст")
            return
        }
        joinByLink(clipboard)
    }

    private func joinByLink(_ link: String) {
        guard let url = URL(string: link),
              url.scheme == "iwish",
              url.host == "join" else {
            joinStatus = .error("Неверная ссылка")
            return
        }

        joinStatus = .joining
        // Placeholder -- real implementation will use CKShare accept
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            joinStatus = .success("Список")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
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
        let cutoutPath = UIBezierPath(roundedRect: scanRect, cornerRadius: 12)
        overlayPath.append(cutoutPath)
        overlayPath.usesEvenOddFillRule = true

        let maskLayer = CAShapeLayer()
        maskLayer.path = overlayPath.cgPath
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = UIColor.black.withAlphaComponent(0.5).cgColor
        view.layer.addSublayer(maskLayer)

        // Corner brackets
        let bracketLength: CGFloat = 30
        let bracketWidth: CGFloat = 3
        let bracketColor = UIColor.white

        func addCorner(x: CGFloat, y: CGFloat, isLeft: Bool, isTop: Bool) {
            let horizontal = UIView(frame: CGRect(
                x: isLeft ? x : x - bracketLength,
                y: isTop ? y : y - bracketWidth,
                width: bracketLength,
                height: bracketWidth
            ))
            horizontal.backgroundColor = bracketColor
            horizontal.layer.cornerRadius = bracketWidth / 2

            let vertical = UIView(frame: CGRect(
                x: isLeft ? x : x - bracketWidth,
                y: isTop ? y : y - bracketLength,
                width: bracketWidth,
                height: bracketLength
            ))
            vertical.backgroundColor = bracketColor
            vertical.layer.cornerRadius = bracketWidth / 2

            view.addSubview(horizontal)
            view.addSubview(vertical)
        }

        addCorner(x: scanRect.minX, y: scanRect.minY, isLeft: true, isTop: true)
        addCorner(x: scanRect.maxX, y: scanRect.minY, isLeft: false, isTop: true)
        addCorner(x: scanRect.minX, y: scanRect.maxY, isLeft: true, isTop: false)
        addCorner(x: scanRect.maxX, y: scanRect.maxY, isLeft: false, isTop: false)

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

        // Close button (top-left, text style)
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Закрыть", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 17)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
        ])

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    @objc private func closeTapped() {
        captureSession.stopRunning()
        onCancel?()
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                    didOutput metadataObjects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              metadataObject.type == .qr,
              let stringValue = metadataObject.stringValue else { return }

        MainActor.assumeIsolated {
            captureSession.stopRunning()
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            onCodeScanned?(stringValue)
        }
    }
}
