import Foundation
import StoreKit
import UIKit
import os.log

/// Управляет system review prompt + ссылкой "Оценить" в Settings.
///
/// **Дизайн:**
/// - System prompt запрашиваем максимум 1 раз в неделю и не ранее 3-го foreground'а app
///   (Apple ограничивает 3 prompts в год сам по себе).
/// - Запрос идёт после позитивного UX-события (становление app active) — но НЕ при
///   первом старте (не успели накопить впечатлений).
/// - Settings → "Оценить I Wish" открывает App Store с автоматом write-review.
@MainActor
enum ReviewService {
    private static let log = Logger(subsystem: "RUGyron.IWish", category: "Review")
    private static let appStoreID = "6762267281"

    private static let foregroundCountKey = "iwish_review_foreground_count"
    private static let lastPromptKey = "iwish_review_last_prompt"
    private static let minForegroundsBeforePrompt = 3
    private static let promptCooldown: TimeInterval = 7 * 24 * 3600 // 7 days

    /// Сбрасывает badge counter app icon. Вызывать при `scenePhase == .active`.
    static func resetBadge() {
        Task { @MainActor in
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
        }
    }

    /// Возможно запросить system review prompt при foreground'е.
    /// Внутренние gate'ы: не чаще раз в неделю + минимум 3 foreground'а.
    static func maybeRequestReviewOnForeground() {
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: foregroundCountKey) + 1
        defaults.set(count, forKey: foregroundCountKey)
        guard count >= minForegroundsBeforePrompt else { return }
        let last = defaults.double(forKey: lastPromptKey)
        let now = Date().timeIntervalSince1970
        guard last == 0 || (now - last) > promptCooldown else { return }
        defaults.set(now, forKey: lastPromptKey)
        log.info("Requesting system review prompt (foreground=\(count, privacy: .public))")
        Task { @MainActor in
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first {
                AppStore.requestReview(in: scene)
            }
        }
    }

    /// Открыть App Store на странице write-review. Вызывается из Settings → "Оценить".
    static func openAppStoreReview() {
        guard let url = URL(string: "itms-apps://apps.apple.com/app/id\(appStoreID)?action=write-review") else { return }
        UIApplication.shared.open(url) { success in
            if !success, let fallback = URL(string: "https://apps.apple.com/app/id\(appStoreID)") {
                UIApplication.shared.open(fallback)
            }
        }
    }
}
