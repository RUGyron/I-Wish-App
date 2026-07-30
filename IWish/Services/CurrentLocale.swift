import Foundation

/// Текущий язык юзера в формате BCP 47 для серверного использования (CF push templates, ASC).
/// Возвращает один из 10 supported языков; для остальных fallback на `en`.
///
/// Маппинг:
/// - `ru` → ru (Россия, СНГ)
/// - `en` → en (default + большинство англоязычных)
/// - `es` → es (Spain + Latin America)
/// - `de` → de
/// - `fr` → fr
/// - `it` → it
/// - `ja` → ja
/// - `zh-Hans` → китайский упрощённый
/// - `ko` → ko
/// - `pt-BR` → Бразилия (pt-PT тоже маппится сюда — у нас один PT)
enum CurrentLocale {
    static let supported: Set<String> = [
        "ru", "en", "es", "de", "fr", "it", "ja", "zh-Hans", "ko", "pt-BR"
    ]

    /// Текущий язык юзера для отправки на сервер. Гарантированно из `supported`.
    static func identifier() -> String {
        guard let raw = Locale.current.language.languageCode?.identifier else { return "en" }
        // Особая обработка для языков с region/script вариантами.
        if raw == "zh" {
            let script = Locale.current.language.script?.identifier
            // Simplified Chinese — наш единственный вариант поддержки.
            if script == "Hans" || script == nil { return "zh-Hans" }
            return "en" // zh-Hant и др. — fallback на EN
        }
        if raw == "pt" {
            // pt-BR — наш единственный вариант. pt-PT тоже считаем BR (одно покрытие лучше чем english fallback).
            return "pt-BR"
        }
        if supported.contains(raw) {
            return raw
        }
        return "en"
    }
}
