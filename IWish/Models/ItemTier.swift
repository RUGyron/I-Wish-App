import Foundation

enum ItemTier: String, Codable, CaseIterable, Sendable, Identifiable {
    case must
    case maybe
    case idea

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .must:  return "🔥"
        case .maybe: return "🤔"
        case .idea:  return "💭"
        }
    }

    var label: String {
        switch self {
        case .must:  return "Обязательно"
        case .maybe: return "Пока думаю"
        case .idea:  return "Просто идея"
        }
    }

    static var defaultTier: ItemTier { .maybe }
}
