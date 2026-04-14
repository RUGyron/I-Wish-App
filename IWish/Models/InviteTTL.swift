import Foundation

enum InviteTTL: String, Codable, CaseIterable, Sendable, Identifiable {
    case minutes15 = "15m"
    case hour1 = "1h"
    case hours24 = "24h"
    case noExpiry = "none"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minutes15: return "15 мин"
        case .hour1:     return "1 час"
        case .hours24:   return "24 часа"
        case .noExpiry:  return "\u{221E}"
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .minutes15: return 15 * 60
        case .hour1:     return 60 * 60
        case .hours24:   return 24 * 60 * 60
        case .noExpiry:  return nil
        }
    }
}
