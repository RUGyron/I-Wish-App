import Foundation
import SwiftUI

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

    /// Цвет для индикации важности (полоска слева у карточки, бейдж в детальном виде).
    var stripeColor: Color {
        switch self {
        case .must:  return Color(red: 0.91, green: 0.30, blue: 0.30)
        case .maybe: return Color(red: 0.95, green: 0.60, blue: 0.20)
        case .idea:  return Color(red: 0.40, green: 0.60, blue: 0.85)
        }
    }

    static let defaultTier: ItemTier = .maybe
}
