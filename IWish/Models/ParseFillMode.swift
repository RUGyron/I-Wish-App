import Foundation

/// Режим автозаполнения формы желания при вставке ссылки.
enum ParseFillMode: String, CaseIterable, Identifiable {
    /// Ничего не трогать — даже пустые поля. Юзер сам ввёл всё.
    case off
    /// Заполнять только пустые поля. Ручной ввод не перезаписывается.
    case empty
    /// Всегда перезаписывать — даже если юзер уже ввёл.
    case overwrite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off:       return String(localized: "Don’t fill")
        case .empty:     return String(localized: "Only empty fields")
        case .overwrite: return String(localized: "Always overwrite")
        }
    }
}
