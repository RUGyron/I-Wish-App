import SwiftUI

/// Рендерит mesh-градиент по UUID для дефолтной обложки айтема/вишлиста.
/// Если есть `imageData` — рендерит фото вместо градиента.
struct DefaultCoverView: View {
    let id: UUID
    var imageData: Data? = nil
    var emoji: String? = nil

    var body: some View {
        ZStack {
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                meshBackground
                if let emoji {
                    Text(emoji)
                        .font(.system(size: 40))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .titaniumBorder(cornerRadius: 12)
    }

    private var meshBackground: some View {
        let colors = DefaultCoverGenerator.colors(for: id)
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
