import Testing
import UIKit
@testable import IWish

@Suite("ImageCompressor")
struct ImageCompressorTests {
    @Test("compress returns data ≤ targetMaxBytes for typical input")
    func compressSmall() throws {
        let image = makeImage(size: CGSize(width: 800, height: 600), color: .red)
        let data = try #require(ImageCompressor.compress(image))
        #expect(data.count <= ImageCompressor.targetMaxBytes)
    }

    @Test("compress downscales oversized image")
    func compressLarge() throws {
        let image = makeImage(size: CGSize(width: 4000, height: 3000), color: .blue)
        let data = try #require(ImageCompressor.compress(image))
        let restored = try #require(UIImage(data: data))
        let maxEdge = max(restored.size.width, restored.size.height)
        #expect(maxEdge <= ImageCompressor.maxEdge + 1)  // ±1 для rounding
    }

    @Test("compress preserves small image dimensions")
    func compressSmallPreserves() throws {
        let original = makeImage(size: CGSize(width: 200, height: 200), color: .green)
        let data = try #require(ImageCompressor.compress(original))
        let restored = try #require(UIImage(data: data))
        #expect(abs(restored.size.width - 200) < 2)
    }

    /// Produces a UIImage at scale=1 so that JPEG round-trip preserves size.
    /// Real-world user-supplied images (camera, photo library) also have scale=1,
    /// so this matches production behavior.
    private func makeImage(size: CGSize, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
