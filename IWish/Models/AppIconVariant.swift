import Foundation

enum AppIconVariant: String, Codable, CaseIterable, Sendable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:  return "Авто"
        case .light: return "Светлая"
        case .dark:  return "Тёмная"
        }
    }
}
