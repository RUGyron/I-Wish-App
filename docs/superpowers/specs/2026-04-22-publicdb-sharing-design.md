# Public DB Sharing — Design Spec

**Дата:** 2026-04-22
**Заменяет:** CKShare-based sharing (2026-04-18)

## Проблема

CKShare + SwiftData = нестабильно. Zone mirroring ненадёжен, accept flow требует reflection hack, конфликты непредсказуемы.

## Решение

Shared wishlists хранятся в **CloudKit Public Database** как обычные CKRecord. Никаких CKShare, зон, mirroring. Прямые CRUD операции.

## Record Types (Public DB)

### SharedWishlist
| Поле | Тип | Описание |
|------|-----|----------|
| wishlistID | String (UUID) | ID вишлиста |
| name | String | Название |
| coverEmoji | String? | Эмодзи обложки |
| ownerRecordID | String | CKRecord.ID.recordName владельца |
| ownerName | String? | Имя владельца |
| memberRecordIDs | [String] | Массив CKRecord.ID.recordName участников |
| memberRoles | [String] | Массив ролей ("editor"/"viewer"), индекс = индексу в memberRecordIDs |
| updatedAt | Date | Последнее обновление |

### SharedItem
| Поле | Тип | Описание |
|------|-----|----------|
| itemID | String (UUID) | ID айтема |
| wishlistID | String (UUID) | FK на SharedWishlist |
| name | String | Название |
| tier | String | "must"/"maybe"/"idea" |
| price | Double? | Цена |
| currency | String | "RUB"/"USD" |
| url | String? | Ссылка |
| coverEmoji | String? | Эмодзи |
| sortIndex | Double | Порядок |
| isArchived | Bool | В архиве |
| updatedAt | Date | Последнее обновление |

### ShareLink (уже есть)
Без изменений — shortID → wishlistID маппинг для QR/ссылки.

## Owner Flow

1. "Поделиться" → создаёт SharedWishlist + SharedItem записи в PublicDB
2. Генерирует QR/ссылку (как сейчас, через ShareLink)
3. Любые локальные изменения → push в PublicDB

## Receiver Flow

1. Scan QR → resolve ShareLink → получает wishlistID
2. InvitePreviewSheet показывает данные из SharedWishlist
3. "Принять" → добавляет свой userRecordID в memberRecordIDs
4. Fetch SharedWishlist + SharedItems → создаёт локальные копии в SwiftData
5. Wishlist появляется мгновенно

## Sync

- **Push:** после любого изменения локального shared wishlist → update PublicDB
- **Pull:** при открытии shared wishlist → fetch из PublicDB, мержим
- **Notifications:** CKSubscription на SharedItem/SharedWishlist changes (фоновые push)
- **Конфликты:** `recordChangeTag` + retry при конфликте (3 попытки)

## Что удаляем

- Весь CKShare код (createCKShare, deleteCKShare, acceptShareMetadata, etc.)
- Mirror/reflection hack
- CKAcceptSharesOperation
- Zone mirroring зависимость

## Что сохраняем

- ShareLink в PublicDB (для QR/ссылок)
- InvitePreviewSheet UI
- ShareWishlistSheet UI
- ParticipantsView UI
- Toast система
- Universal Links
