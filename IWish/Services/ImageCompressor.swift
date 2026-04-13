import UIKit

enum ImageCompressor {
    static let maxEdge: CGFloat = 1024
    static let primaryQuality: CGFloat = 0.7
    static let fallbackQuality: CGFloat = 0.5
    static let targetMaxBytes: Int = 500_000  // 500 KB

    /// Сжимает изображение в JPEG, стремится уложиться в targetMaxBytes.
    /// Сначала ресайз до maxEdge, потом quality 0.7. Если всё ещё больше — quality 0.5.
    static func compress(_ image: UIImage) -> Data? {
        let resized = image.resized(maxEdge: maxEdge)
        if let primary = resized.jpegData(compressionQuality: primaryQuality),
           primary.count <= targetMaxBytes {
            return primary
        }
        return resized.jpegData(compressionQuality: fallbackQuality)
    }
}

private extension UIImage {
    func resized(maxEdge: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxEdge else { return self }
        let scale = maxEdge / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in self.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
