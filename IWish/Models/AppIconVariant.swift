import Foundation

enum AppIconVariant: String, Codable, CaseIterable, Sendable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Светлая"
        case .dark:  return "Тёмная"
        }
    }

    var symbolName: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark:  return "moon.fill"
        }
    }
}
