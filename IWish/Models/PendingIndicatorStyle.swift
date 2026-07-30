import Foundation
import SwiftUI

/// Стиль визуализации pending-sync state на уровне item / wishlist tile.
/// Юзер выбирает любимый в Settings → Дизайн → Pending indicator.
enum PendingIndicatorStyle: String, CaseIterable, Identifiable {
    /// Pill «Ждёт сети» с иконкой cloud.slash, orange accent — макс ясность.
    case pill
    /// Оранжевая полоска слева вместо tier-цвета. Минималистично, но без слов.
    case stripe
    /// Faded row + clock.arrow.circlepath в углу обложки. Mail-style.
    case clock
    /// Просто оранжевая точка 10pt. Самый лаконичный.
    case dot

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pill:   return String(localized: "Pill with text")
        case .stripe: return String(localized: "Orange side stripe")
        case .clock:  return String(localized: "Faded + clock icon")
        case .dot:    return String(localized: "Orange dot")
        }
    }
}
