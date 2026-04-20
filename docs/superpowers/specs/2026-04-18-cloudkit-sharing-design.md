# CloudKit Sharing — Design Spec

**Дата:** 2026-04-18
**Статус:** Draft v1
**Зависит от:** основная спека `2026-04-14-iwish-design.md` (раздел 6)

---

## Summary

Полноценный invite flow для совместных вишлистов: Owner создаёт шеру → QR с ссылкой → Receiver сканирует → видит invite preview → принимает → shared wishlist появляется в его списке.

---

## Решения (из brainstorm)

| Вопрос | Решение |
|--------|---------|
| Передача invite | Кастомный URL (`github.io/j/{shortID}`) + Universal Links + fallback landing |
| Маппинг shortID → CKShare | CloudKit Public Database, record type `ShareLink` |
| Invite preview | Название + эмодзи + имя owner'а + роль + кол-во items |
| ModelContainer | `.automatic` (private + shared в одном контейнере) |
| TTL ротация | При запуске приложения (проверка всех активных шер) |

---

## Owner Flow

1. Свайп по вишлисту → "Поделиться" → `ShareWishlistSheet`
2. Выбор роли (Редактор / Просмотр) и TTL (15м / 1ч / 24ч / 7д / Без срока)
3. Лоадер 1-2 сек пока создаётся шера:
   - Создаётся `CKShare` в private DB с выбранной ролью
   - Создаётся `ShareLink` record в Public DB: `{shortID, ckShareURL, wishlistName, wishlistEmoji, ownerName, role, itemCount, expiresAt}`
   - Генерируется QR из `https://rugyron.github.io/I-Wish-App/j/{shortID}`
4. QR появляется + кнопки "Поделиться" / "Копировать ссылку"
5. Под QR: "Действует до HH:MM"
6. Смена роли или TTL → пересоздание шеры (старая ссылка умирает, новый QR)

### Отмена и ротация

- "Отменить приглашение" → удаляет CKShare + PublicDB record. Существующие участники остаются.
- При запуске приложения: проверяются все `ShareLink` records с `expiresAt < now` → удаляются (CKShare + PublicDB record).

---

## Receiver Flow

### Сценарий A: скан из приложения

1. "Присоединиться" → QR scanner → считывает URL
2. Парсит `shortID` из URL
3. Query Public DB по `shortID` → получает metadata (название, эмодзи, имя owner'а, роль, кол-во items, ckShareURL)
4. **Invite Preview Sheet** появляется:
   - Эмодзи + название списка
   - "Влад приглашает тебя"
   - Роль: "Редактор" или "Только просмотр"
   - "5 желаний в списке"
   - Кнопка **"Принять"** + **"Отклонить"**
5. "Принять" → лоадер → accept CKShare по `ckShareURL` → wishlist появляется в HomeView
6. "Отклонить" → dismiss, ничего не происходит

### Сценарий B: скан камерой (приложение установлено)

1. Камера → ссылка → Universal Link → приложение открывается
2. Приложение парсит shortID из URL → тот же flow что и сценарий A (шаги 3-6)
3. Invite Preview Sheet показывается автоматически

### Сценарий C: скан камерой (приложения нет)

1. Камера → ссылка → Universal Link не перехватывается → Safari
2. GitHub Pages landing: логотип + "Скачай I Wish" + кнопка App Store

---

## Invite Preview Sheet (новый UI)

Модалка `.medium` detent:

```
    ┌─────────────────────────────┐
    │         🎂                  │
    │    День рождения            │
    │                             │
    │  Влад приглашает тебя       │
    │  Роль: Редактор             │
    │  5 желаний в списке         │
    │                             │
    │  ┌─────────────────────┐    │
    │  │     Принять         │    │
    │  └─────────────────────┘    │
    │       Отклонить             │
    └─────────────────────────────┘
```

- "Принять" — `.borderedProminent`, зелёный accent
- "Отклонить" — `.plain`, серый
- Лоадер при загрузке metadata из Public DB
- Ошибка: "Приглашение недействительно" если shortID не найден или просрочен

---

## После принятия

- Shared wishlist появляется в HomeView среди обычных списков
- Визуальное отличие: бейдж с иконкой людей + "Общий с Влад"
- Viewer: видит items, не может редактировать/добавлять/удалять
- Editor: полный доступ как owner, кроме управления участниками
- Owner видит участников в ParticipantsView (уже существует)

---

## Технические изменения

### Новые файлы
- `CloudKitSharingService` — создание/accept/revoke CKShare, CRUD PublicDB
- `InvitePreviewSheet` — UI invite preview

### Изменения в существующих файлах
- `ModelContainerFactory` — `.private(...)` → `.automatic`
- `ShareManager` — вместо фейкового URL → реальный CKShare + PublicDB
- `JoinWishlistSheet` — `joinByLink` → резолвит shortID → показывает InvitePreviewSheet
- `IWishApp` — обработка Universal Links для incoming shares
- `HomeView` — бейдж "Общий" на shared wishlists

### Universal Links
- `apple-app-site-association` файл на GitHub Pages (`rugyron.github.io`)
- Ассоциация: `applinks:rugyron.github.io` в entitlements
- Path pattern: `/I-Wish-App/j/*`

### GitHub Pages landing
- Статическая HTML страница по `/I-Wish-App/j/{anything}`
- Логотип + "Скачай I Wish в App Store" + кнопка
- Работает только когда Universal Link не перехвачен (приложение не установлено)

### CloudKit Public DB schema
- Record type: `ShareLink`
- Fields: `shortID` (String, queryable), `ckShareURL` (String), `wishlistName` (String), `wishlistEmoji` (String), `ownerName` (String), `role` (String), `itemCount` (Int64), `expiresAt` (Date)

---

## Error Handling

| Ситуация | Что видит юзер |
|----------|----------------|
| Нет интернета при создании шеры | "Нет подключения к интернету" в ShareWishlistSheet |
| shortID не найден в Public DB | "Приглашение недействительно или истекло" |
| CKShare accept fail | "Не удалось присоединиться. Попробуйте ещё раз" |
| iCloud аккаунт не настроен | "Войдите в iCloud для совместных списков" |

---

## Не входит в scope

- BGAppRefreshTask для TTL (добавим позже при необходимости)
- Уведомления о новых items в shared wishlist
- Chat/комментарии в shared wishlists
- Share Extension (отдельный milestone M8)
