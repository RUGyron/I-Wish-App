import SwiftUI
import AVFoundation
import AudioToolbox

struct JoinWishlistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var linkText = ""
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
                // Description
                VStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text("Присоединиться к списку")
                        .font(.title3.weight(.semibold))
                    Text("Отсканируй QR-код или вставь ссылку-приглашение")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                // Scan QR button
                Button {
                    showingScanner = true
                } label: {
                    Label("Сканировать QR-код", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)

                // Divider
                HStack {
                    Rectangle().fill(.quaternary).frame(height: 1)
                    Text("или")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Rectangle().fill(.quaternary).frame(height: 1)
                }
                .padding(.horizontal, 32)

                // Paste link
                VStack(spacing: 12) {
                    TextField("Ссылка приглашения", text: $linkText)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal)

                    HStack(spacing: 12) {
                        Button {
                            if let clipboard = UIPasteboard.general.string {
                                linkText = clipboard
                            }
                        } label: {
                            Label("Вставить", systemImage: "doc.on.clipboard")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            joinByLink()
                        } label: {
                            Text("Войти")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(linkText.isEmpty)
                    }
                    .controlSize(.large)
                    .padding(.horizontal)
                }

                // Status
                statusView

                Spacer()
            }
            .navigationTitle("Присоединиться")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                QRScannerView { code in
                    linkText = code
                    showingScanner = false
                    joinByLink()
                }
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

    private func joinByLink() {
        guard let url = URL(string: linkText),
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

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

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

        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),
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
