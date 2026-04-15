import Foundation

enum InputLimits {
    static let wishlistName = 60
    static let itemName = 100
    static let itemDescription = 500
    static let itemURL = 2000
    static let maxItemsPerWishlist = 500
    static let maxEmptyWishlists = 3

    static func truncate(_ text: String, to limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) : text
    }
}
