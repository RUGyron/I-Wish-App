import Foundation

/// Хелпер для per-field LWW timestamps хранимых в `fieldTimestampsJSON: Data?`.
/// Формат: JSON `{"name": "2026-05-20T12:00:00Z", "tierRaw": "2026-05-20T11:55:00Z"}`.
///
/// При offline-sync клиент мерджит per-field на основе этих timestamps vs server'ных:
/// поле с более новым timestamp побеждает. Минимум потерь данных при independent edits.
enum FieldTimestamps {
    private static let iso = ISO8601DateFormatter()

    /// Прочитать map из JSON blob.
    static func decode(_ data: Data?) -> [String: Date] {
        guard let data,
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        var result: [String: Date] = [:]
        for (k, v) in raw {
            if let d = iso.date(from: v) { result[k] = d }
        }
        return result
    }

    /// Сериализовать map обратно в JSON blob.
    static func encode(_ map: [String: Date]) -> Data? {
        let raw: [String: String] = map.mapValues { iso.string(from: $0) }
        return try? JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys])
    }

    /// Обновить timestamp поля на текущее время. Возвращает новый JSON blob.
    static func touch(_ data: Data?, field: String, at when: Date = Date()) -> Data? {
        var map = decode(data)
        map[field] = when
        return encode(map)
    }

    /// Обновить timestamps нескольких полей сразу.
    static func touch(_ data: Data?, fields: [String], at when: Date = Date()) -> Data? {
        var map = decode(data)
        for f in fields { map[f] = when }
        return encode(map)
    }

    /// Получить timestamp конкретного поля.
    static func timestamp(of field: String, in data: Data?) -> Date? {
        decode(data)[field]
    }
}
