import Foundation

enum InputLimits {
    static let wishlistName = 60
    static let itemName = 100
    static let itemDescription = 500
    static let itemURL = 2000

    /// Сколько активных (не-архивных) wishlist'ов можно держать одному юзеру.
    /// Лимит обусловлен бесплатным тарифом Firestore (Spark): 1 GB storage суммарно.
    static let maxWishlistsPerUser = 30

    /// Сколько активных (не-архивных) items в одном wishlist.
    static let maxItemsPerWishlist = 50

    /// Сколько пустых wishlist'ов можно создать подряд (UX-защита от спама).
    static let maxEmptyWishlists = 3

    /// Сколько HTTP-запросов к Firestore приложение делает в минуту.
    /// Защита от runaway loops. Spark plan day-quota (50K reads/day = ~33/min sustained)
    /// в обычной жизни не пробивается; cap 300 обеспечивает запас под burst при частых правках.
    static let maxFirestoreRequestsPerMinute = 300

    /// Минимальный интервал (сек) между авто-refresh'ами личных wishlist'ов
    /// и shared wishlists. Manual pull-to-refresh от юзера не подчиняется этому
    /// throttle'у (в нём другой путь).
    static let minWishlistsRefreshInterval: TimeInterval = 30

    /// Минимальный интервал (сек) между авто-refresh'ами items одного wishlist'а.
    static let minItemsRefreshInterval: TimeInterval = 15

    static func truncate(_ text: String, to limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) : text
    }
}
