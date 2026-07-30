import Foundation

enum AppIconVariant: String, Codable, CaseIterable, Sendable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return String(localized: "Light")
        case .dark:  return String(localized: "Dark")
        }
    }

    var previewAsset: String {
        switch self {
        case .light: return "IconPreviewLight"
        case .dark:  return "IconPreviewDark"
        }
    }

    var alternateIconName: String? {
        switch self {
        case .light: return nil
        case .dark:  return "DarkIcon"
        }
    }
}
