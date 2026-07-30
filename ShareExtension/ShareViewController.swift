import UIKit
import SwiftUI
import UniformTypeIdentifiers
import os.log

/// Entry point Share Extension. Извлекает URL + title + preview image из NSExtensionContext,
/// показывает SwiftUI sheet с picker'ом вишлистов, при сохранении пишет PendingShare в App Group.
///
/// **Принцип:** Share Extension не делает сетевых запросов и не работает с Firebase. Только локальная
/// очередь. Main app при `didBecomeActive` процессит очередь — создаёт Item через DataService,
/// удаляет запись. Это даёт надёжный UX (extension быстро закрывается, юзер сразу обратно в Ozon)
/// и упрощает архитектуру (нет дублирования auth/network логики в extension).
class ShareViewController: UIViewController {
    private let log = Logger(subsystem: "RUGyron.IWish.ShareExtension", category: "Share")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(white: 0.05, alpha: 0.4) : UIColor(white: 1, alpha: 0.4)
        }
        Task {
            await extractAndPresent()
        }
    }

    private func extractAndPresent() async {
        let context = self.extensionContext
        guard let inputItems = context?.inputItems as? [NSExtensionItem], !inputItems.isEmpty else {
            await complete()
            return
        }

        var url: URL?
        var pageTitle: String?
        var imageData: Data?

        for item in inputItems {
            if pageTitle == nil, let s = item.attributedContentText?.string, !s.isEmpty {
                pageTitle = s
            }
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let raw = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) {
                        if let extractedURL = raw as? URL {
                            url = extractedURL
                        } else if let s = raw as? String, let u = URL(string: s) {
                            url = u
                        }
                    }
                }
                // PropertyList (Safari extension daemon) — содержит title + URL + selectionText.
                if provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) {
                    if let raw = try? await provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier, options: nil),
                       let dict = (raw as? NSDictionary)?["NSExtensionJavaScriptPreprocessingResultsKey"] as? [String: Any] {
                        if url == nil, let urlStr = dict["URL"] as? String, let u = URL(string: urlStr) {
                            url = u
                        }
                        if pageTitle == nil, let t = dict["title"] as? String, !t.isEmpty {
                            pageTitle = t
                        }
                    }
                }
                if imageData == nil, provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let raw = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) {
                        if let img = raw as? UIImage {
                            imageData = compressedJPEG(img)
                        } else if let imgURL = raw as? URL, let img = UIImage(contentsOfFile: imgURL.path) {
                            imageData = compressedJPEG(img)
                        } else if let data = raw as? Data, let img = UIImage(data: data) {
                            imageData = compressedJPEG(img)
                        }
                    }
                }
            }
        }

        guard let url else {
            log.warning("No URL in inputItems")
            await complete()
            return
        }

        await MainActor.run {
            presentUI(url: url, sharedTitle: pageTitle, imageData: imageData)
        }
    }

    @MainActor
    private func presentUI(url: URL, sharedTitle: String?, imageData: Data?) {
        let host = UIHostingController(
            rootView: ShareView(
                url: url,
                sharedTitle: sharedTitle,
                imageData: imageData,
                onCancel: { [weak self] in
                    Task { @MainActor [weak self] in await self?.complete() }
                },
                onSave: { [weak self] in
                    Task { @MainActor [weak self] in await self?.complete() }
                }
            )
        )
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func compressedJPEG(_ image: UIImage) -> Data? {
        // Max edge 1024 + quality 0.7 — соответствует ImageCompressor в основном app.
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

    @MainActor
    private func complete() async {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
