import Testing
import SwiftData
import Foundation
@testable import IWish

@Suite("Item model")
struct ItemModelTests {
    @Test("init applies defaults")
    func initDefaults() {
        let item = Item(name: "AirPods")
        #expect(item.name == "AirPods")
        #expect(item.tier == .maybe)
        #expect(item.currency == "RUB")
        #expect(item.price == nil)
        #expect(item.descriptionText == nil)
        #expect(item.isArchived == false)
        #expect(item.url == nil)
        #expect(item.probationEndAt == nil)
        #expect(item.sortIndex == 1000.0)
    }

    @Test("custom sortIndex is preserved")
    func customSortIndex() {
        let item = Item(name: "x", sortIndex: 1500.0)
        #expect(item.sortIndex == 1500.0)
    }

    @Test("relationship to wishlist round-trips")
    func relationshipRoundTrip() throws {
        let container = try ModelContainer(
            for: Wishlist.self, Item.self, AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let wishlist = Wishlist(name: "Owner")
        context.insert(wishlist)
        let item = Item(name: "Belongs", tier: .must)
        item.wishlist = wishlist
        context.insert(item)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Wishlist>())
        #expect((fetched.first?.items ?? []).count == 1)
        #expect((fetched.first?.items ?? []).first?.name == "Belongs")
    }
}
