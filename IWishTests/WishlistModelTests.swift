import Testing
import SwiftData
import Foundation
@testable import IWish

@Suite("Wishlist model")
struct WishlistModelTests {
    @Test("init sets defaults")
    func initDefaults() throws {
        let wishlist = Wishlist(name: "Hello")
        #expect(wishlist.name == "Hello")
        #expect(wishlist.coverImageData == nil)
        #expect(wishlist.coverEmoji == nil)
        #expect((wishlist.items ?? []).isEmpty)
        #expect(abs(wishlist.createdAt.timeIntervalSinceNow) < 1.0)
        #expect(wishlist.createdAt == wishlist.updatedAt)
    }

    @Test("ids are unique across instances")
    func uniqueIds() {
        let a = Wishlist(name: "A")
        let b = Wishlist(name: "B")
        #expect(a.id != b.id)
    }

    @Test("can persist and reload via in-memory ModelContainer")
    func persistAndReload() throws {
        let container = try ModelContainer(
            for: Wishlist.self, Item.self, AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let wishlist = Wishlist(name: "Persist me")
        context.insert(wishlist)
        try context.save()

        let descriptor = FetchDescriptor<Wishlist>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Persist me")
    }
}
