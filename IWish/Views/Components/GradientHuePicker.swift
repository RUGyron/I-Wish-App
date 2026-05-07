import SwiftUI

/// Радужный слайдер для выбора оттенка градиента обложки wishlist'а.
/// Превью градиента сверху анимирует hue в реальном времени, ползунок снизу — рисует радугу.
struct GradientHuePicker: View {
    @Binding var hue: Double  // 0...1

    var body: some View {
        VStack(spacing: 16) {
            preview
            slider
                .frame(height: 36)
        }
    }

    @ViewBuilder
    private var preview: some View {
        let colors = DefaultCoverGenerator.colors(forHue: hue)
        MeshGradient(
            width: 3, height: 3,
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
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: hue)
    }

    private var slider: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                rainbow
                    .frame(height: 28)
                    .clipShape(Capsule())

                thumb
                    .offset(x: thumbOffsetX(in: geo.size.width))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = max(0, min(geo.size.width, value.location.x))
                                hue = x / geo.size.width
                            }
                    )
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private var rainbow: some View {
        let stops = stride(from: 0.0, through: 1.0, by: 0.05).map { h in
            Gradient.Stop(color: Color(hue: h, saturation: 0.85, brightness: 0.92), location: h)
        }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    private var thumb: some View {
        Circle()
            .fill(Color(hue: hue, saturation: 0.85, brightness: 0.95))
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            .frame(width: 32, height: 32)
    }

    private func thumbOffsetX(in width: CGFloat) -> CGFloat {
        let x = width * hue - 16
        return max(0, min(width - 32, x))
    }
}
