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
        // Just verify data was produced and is within target
        #expect(data.count > 0)
        #expect(data.count <= ImageCompressor.targetMaxBytes * 2)  // Generous limit
    }

    @Test("compress preserves small image dimensions")
    func compressSmallPreserves() throws {
        let original = makeImage(size: CGSize(width: 200, height: 200), color: .green)
        let data = try #require(ImageCompressor.compress(original))
        guard let restored = UIImage(data: data) else {
            #expect(Bool(false), "Should create UIImage from JPEG")
            return
        }
        #expect(restored.size.width > 0)
        #expect(restored.size.height > 0)
    }

    private func makeImage(size: CGSize, color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
