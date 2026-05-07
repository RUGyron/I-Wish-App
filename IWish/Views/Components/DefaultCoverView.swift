import SwiftUI

/// Рендерит mesh-градиент по UUID для дефолтной обложки айтема/вишлиста.
/// Если есть `imageData` — рендерит фото вместо градиента.
struct DefaultCoverView: View {
    let id: UUID
    var imageData: Data? = nil
    var emoji: String? = nil
    var gradientSeed: Int? = nil
    var gradientHue: Double? = nil

    var body: some View {
        if let imageData, let uiImage = UIImage(data: imageData) {
            // GeometryReader takes the proposed size (e.g. 60×60 from parent's .frame),
            // passes exact dimensions to Image so scaledToFill fills correctly,
            // then clipped() and clipShape prevent any rendering overflow.
            GeometryReader { geo in
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .titaniumBorder(cornerRadius: 12)
        } else {
            ZStack {
                meshBackground
                if let emoji {
                    Text(emoji)
                        .font(.system(size: 40))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .titaniumBorder(cornerRadius: 12)
        }
    }

    private var meshBackground: some View {
        let colors: [Color] = {
            if let hue = gradientHue {
                return DefaultCoverGenerator.colors(forHue: hue)
            }
            if let seed = gradientSeed, seed != 0 {
                return DefaultCoverGenerator.colors(forSeed: seed)
            }
            // Fallback: deterministic hash from UUID string (stable across devices)
            return DefaultCoverGenerator.colors(forSeed: DefaultCoverGenerator.stableHash(id.uuidString))
        }()
        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                .init(0, 0),   .init(0.5, 0),   .init(1, 0),
                .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                .init(0, 1),   .init(0.5, 1),   .init(1, 1),
            ],
            colors: [
                colors[0], colors[1], colors[2],
                colors[1], colors[2], colors[0],
                colors[2], colors[0], colors[1],
            ]
        )
    }
}

#Preview {
    HStack {
        DefaultCoverView(id: UUID())
            .frame(width: 80, height: 80)
        DefaultCoverView(id: UUID(), emoji: "🎧")
            .frame(width: 80, height: 80)
    }
    .padding()
}
