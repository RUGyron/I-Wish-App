import Foundation

enum ItemTier: String, Codable, CaseIterable, Sendable, Identifiable {
    case must
    case maybe
    case idea

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .must:  return "flame.fill"
        case .maybe: return "questionmark.circle"
        case .idea:  return "lightbulb"
        }
    }

    var emoji: String {
        switch self {
        case .must:  return "\u{1F525}"
        case .maybe: return "\u{1F914}"
        case .idea:  return "\u{1F4AD}"
        }
    }

    var label: String {
        switch self {
        case .must:  return "Обязательно"
        case .maybe: return "Пока думаю"
        case .idea:  return "Просто идея"
        }
    }

    static let defaultTier: ItemTier = .maybe
}
