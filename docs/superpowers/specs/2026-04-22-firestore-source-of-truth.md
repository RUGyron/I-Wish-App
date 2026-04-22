# Firestore Source of Truth — Design Spec

**Дата:** 2026-04-22
**Заменяет:** все предыдущие подходы к синку

## Принцип

**Firestore = единственный source of truth. SwiftData = read-only кеш.**

- Любое создание/изменение/удаление → сначала Firestore, потом обновить кеш
- Чтение → из SwiftData (мгновенно), при открытии экрана — fetch из Firestore → обновить кеш
- Нет сети → видишь кеш, но мутации заблокированы
- Нет конфликтов — SwiftData не генерирует данные

## Auth

- Sign in with Apple **обязателен** — без него приложение не работает
- Кнопка "Не сейчас" убрана
- При запуске: если нет auth → показать Sign in with Apple fullscreen
- UID и имя из Firebase Auth

## Firestore Collections

```
users/{uid}/wishlists/{wishlistID}
  ├── name, coverEmoji, gradientSeed (Int), createdAt, updatedAt
  └── items/{itemID}
        ├── name, tier, price, currency, url, coverEmoji, sortIndex, isArchived, createdAt, updatedAt

shared_wishlists/{wishlistID}
  ├── name, coverEmoji, gradientSeed, ownerUID, ownerName, createdAt, updatedAt
  └── items/{itemID} (same fields)

memberships/{uid}_{wishlistID}
  ├── wishlistID, userUID, role, joinedAt

inviteLinks/{shortID}
  ├── wishlistID, wishlistName, wishlistEmoji, ownerName, role, itemCount, expiresAt
```

**Личные вишлисты** в `users/{uid}/wishlists/` — приватные, только owner видит.
**Шаренные** в `shared_wishlists/` — доступны всем members.

## Data Flow

### Create wishlist
1. Write to Firestore `users/{uid}/wishlists/{id}`
2. On success → insert into SwiftData
3. Show sync indicator ✓

### Edit item
1. Write to Firestore `.../items/{id}`
2. On success → update SwiftData
3. Show sync indicator ✓

### Share wishlist
1. Copy wishlist + items from `users/{uid}/wishlists/{id}` to `shared_wishlists/{id}`
2. Create inviteLink
3. Delete from personal collection (it's now in shared)
4. Update SwiftData

### Accept invite
1. Create membership
2. Fetch shared wishlist + items
3. Insert into SwiftData as cache
4. Navigate to wishlist detail

### Open screen
1. Show SwiftData cache instantly
2. Fetch from Firestore in background
3. Merge into SwiftData (add/update/delete)
4. UI updates via @Query

## Sync Indicator

Navbar subtitle (like before):
- Writing → small spinner
- Success → "iCloud" checkmark (2 sec)
- Error → orange "Нет сети" with retry on tap

## Gradient Seed

`gradientSeed: Int` stored in Firestore alongside wishlist. Generated once at creation (`UUID().hashValue`). Used by `DefaultCoverGenerator.colors(for:)`. Same seed = same gradient on all devices.

## SwiftData Models

Keep Wishlist and Item as @Model but:
- Remove `cloudKitDatabase: .automatic` (already done)
- Add `gradientSeed: Int` to Wishlist
- All mutations go through a `DataService` that writes Firestore first, then updates SwiftData

## DataService (new)

Central service that handles all CRUD:

```swift
@Observable @MainActor
final class DataService {
    let firestore: FirestoreService
    let modelContext: ModelContext
    
    // MARK: - Wishlists
    func createWishlist(name:emoji:) async throws -> Wishlist
    func updateWishlist(_:name:emoji:) async throws
    func deleteWishlist(_:) async throws
    func shareWishlist(_:role:ttl:) async throws -> URL // returns QR URL
    
    // MARK: - Items  
    func addItem(to:name:tier:price:...) async throws -> Item
    func updateItem(_:...) async throws
    func deleteItem(_:) async throws
    
    // MARK: - Sync
    func refreshWishlists() async // fetch all from Firestore, update SwiftData
    func refreshItems(for:) async // fetch items for wishlist
    
    // MARK: - Accept
    func acceptInvite(shortID:) async throws -> Wishlist
}
```

All views call DataService. No direct SwiftData writes from views.
