import UIKit

enum ImageCompressor {
    static let maxEdge: CGFloat = 1024
    static let primaryQuality: CGFloat = 0.7
    static let fallbackQuality: CGFloat = 0.5
    static let targetMaxBytes: Int = 500_000  // 500 KB

    /// Hard cap — даже после fallback quality 0.5 не пускаем больше этого в Firestore.
    /// Firestore document limit = 1 MB; encryptedPayload содержит и другие поля.
    static let hardCapBytes: Int = 900_000

    /// Сжимает изображение в JPEG, стремится уложиться в targetMaxBytes.
    /// Сначала ресайз до maxEdge, потом quality 0.7 → 0.5 → 0.3.
    /// Возвращает nil если даже после всех проходов не уложилось в hardCapBytes —
    /// лучше отказать, чем превысить Firestore limit.
    static func compress(_ image: UIImage) -> Data? {
        let resized = image.resized(maxEdge: maxEdge)
        if let primary = resized.jpegData(compressionQuality: primaryQuality),
           primary.count <= targetMaxBytes {
            return primary
        }
        if let fallback = resized.jpegData(compressionQuality: fallbackQuality),
           fallback.count <= hardCapBytes {
            return fallback
        }
        // Last-resort: уменьшаем ещё раз и quality 0.3.
        let smaller = image.resized(maxEdge: maxEdge / 2)
        if let last = smaller.jpegData(compressionQuality: 0.3),
           last.count <= hardCapBytes {
            return last
        }
        return nil
    }
}

private extension UIImage {
    func resized(maxEdge: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxEdge else { return self }
        let scale = maxEdge / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        // Pin scale to 1 so the output JPEG's pixel dimensions equal `newSize`
        // regardless of device screen scale. Matches the convention for images
        // originating from camera/photo library (which are also scale=1).
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in self.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
