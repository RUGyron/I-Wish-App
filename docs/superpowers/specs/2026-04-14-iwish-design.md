# I Wish — Design Spec

**Дата:** 2026-04-14
**Статус:** Draft v1 (brainstorm complete, waiting review)
**Bundle ID (предварительно):** `com.rugyron.iwish` (уточнить при публикации)
**Минимальная платформа:** iOS 26.0

---

## Summary

**I Wish** — iOS-приложение для ведения персональных и общих списков желаний. Пользователь добавляет желания (товары/впечатления/что угодно), группирует их по уровню важности, делится списками с близкими через QR-код. Ключевые акценты: приватность (end-to-end шифрование через CloudKit), эстетика iOS 26 Liquid Glass, аккуратное UX для импульсных покупок (испытательный срок).

Приложение pet-project, без монетизации, без собственного бэкенда — всё держится на Apple экосистеме (CloudKit + SwiftData + LinkPresentation).

---

## Motivation & User Stories

- **Импульсные покупки вредят бюджету.** Приложение должно мягко откладывать решение («испытательный срок»).
- **Вишлист для дарителя.** Именинник шарит список друзьям — они смотрят, но не могут ничего сломать (read-only роль).
- **Совместные покупки.** Пара ведёт общий список на обустройство квартиры, оба редактируют.
- **URL-first добавление.** Часто желание — это просто ссылка на WB/Ozon. Вставил ссылку — готовый айтем.
- **Приватность важна.** Список желаний — личные данные, сервер (даже Apple) не должен видеть контент.

---

## Architecture

### Stack

- **UI:** SwiftUI (iOS 26+)
- **Local persistence:** SwiftData
- **Cloud sync:** CloudKit через нативный SwiftData-CloudKit mirror
- **Encryption:** `CKRecord.encryptedValues` (Apple native, zero-knowledge)
- **Sharing:** CKShare для collaboration, QR через `CoreImage.CIFilter.qrCodeGenerator`
- **Link preview:** `LinkPresentation.LPMetadataProvider`
- **Share extension:** iOS Share Extension target

### Backend

**CloudKit.** Три зоны CloudKit используются:
- **Private Database** — личные вишлисты пользователя
- **Shared Database** — вишлисты, к которым юзер присоединился как participant
- **Public Database** — НЕ используется. (В brainstorm обсуждался для short-text кодов, но финально выбрано «только QR», поэтому public не нужен.)

Причина выбора: бесплатно навсегда для разработчика (Apple платит за инфру, каждый юзер использует свой iCloud квот), нативная интеграция со SwiftData, встроенный `CKShare` для multi-user редактирования, автоматическое end-to-end шифрование через `encryptedValues`.

### Encryption model

Все user-facing поля (имя вишлиста, имена айтемов, описания, цены, картинки) помечаются как `@Attribute(.encrypt)` через SwiftData schema или используются через `CKRecord.encryptedValues`.

- Apple шифрует значения на устройстве ключами из iCloud Keychain
- Apple infrastructure видит только ciphertext
- Для shared-записей Apple безопасно распространяет ключи через Keychain между participant-устройствами
- Требование: iCloud Keychain должен быть включён (по дефолту так и есть на iPhone)

**Что НЕ шифруется:**
- Системные метаданные CloudKit (IDs, timestamps, share structure)
- Список участников CKShare (Apple нужно для routing)

### Authentication

- **Нет собственного логина.** Приложение полагается на iCloud аккаунт устройства.
- При запуске: `CKContainer.accountStatus()` — если `.noAccount` / `.restricted`, показываем экран «Войди в iCloud для использования I Wish» с `Continue`-кнопкой, которая дёргает системный Settings.
- Стабильный user ID — `CKContainer.userRecordID()` (для идентификации владельца/участника в UI).

### Local storage

**SwiftData** как единственный слой хранения. Модели:
- `Wishlist`
- `Item`
- `AppSettings` (user preferences, локально, НЕ синкается)

Синк со SwiftData-CloudKit mirror автоматический. Offline-first: всё пишется локально, потом догоняет в облако. Конфликты — last-write-wins на уровне поля (стандартное поведение CloudKit).

---

## Data Model

### `Wishlist`

| Поле | Тип | Шифруется | Заметки |
|------|-----|-----------|---------|
| `id` | `UUID` | нет | primary key |
| `name` | `String` | ✓ | имя вишлиста |
| `coverImageData` | `Data?` | ✓ | JPEG blob для фото, nil если генеративный mesh |
| `coverEmoji` | `String?` | ✓ | если юзер поставил эмодзи вместо фото |
| `createdAt` | `Date` | нет | |
| `updatedAt` | `Date` | нет | auto |
| `ownerRecordID` | `String` | нет | CKUserRecordID в строковом виде |
| `items` | `[Item]` | — | relationship |

Связь с CloudKit: CKRecord type `Wishlist`. Для shared — создаётся `CKShare` с rootRecord = wishlist record.

### `Item`

| Поле | Тип | Шифруется | Заметки |
|------|-----|-----------|---------|
| `id` | `UUID` | нет | |
| `name` | `String` | ✓ | имя желания |
| `descriptionText` | `String?` | ✓ | короткое описание, опц. |
| `coverImageData` | `Data?` | ✓ | фото, nil → generative mesh/emoji |
| `coverEmoji` | `String?` | ✓ | |
| `price` | `Decimal?` | ✓ | |
| `currency` | `String` | ✓ | "RUB" / "USD" |
| `url` | `String?` | ✓ | |
| `linkMetadataData` | `Data?` | ✓ | сериализованный `LPLinkMetadata` (кэш rich preview) |
| `tier` | `String` | ✓ | enum: `must` / `maybe` / `idea` |
| `sortIndex` | `Double` | ✓ | порядок внутри tier (`1000.0`, `2000.0`, etc., вставка между — mid point) |
| `probationEndAt` | `Date?` | ✓ | nil если probation не активен |
| `isArchived` | `Bool` | ✓ | soft delete flag |
| `createdAt` | `Date` | нет | |
| `updatedAt` | `Date` | нет | auto |
| `wishlist` | `Wishlist` | — | inverse relationship |

### `AppSettings` (только локально)

| Поле | Тип | Дефолт |
|------|-----|--------|
| `themeMode` | `ThemeMode` | `.system` |
| `defaultCurrency` | `String` | `"RUB"` |
| `defaultInviteTTL` | `InviteTTL` | `.minutes15` |
| `probationEnabledByDefault` | `Bool` | `false` |
| `defaultProbationDuration` | `TimeInterval` | 30 дней |
| `notifyOnProbationEnd` | `Bool` | `false` |
| `selectedAppIcon` | `AppIconVariant` | `.auto` |
| `hasCompletedOnboarding` | `Bool` | `false` |

Enums:
- `ThemeMode = .light | .dark | .system`
- `InviteTTL = .minutes15 | .hour1 | .hours24 | .days7 | .noExpiry`
- `AppIconVariant = .auto | .light | .dark`
  - `.auto` — следует системной теме (юзер один раз поставил, дальше iOS сама переключает иконку под Light/Dark Mode при перерисовке home screen). Реализация: при смене `UITraitCollection.userInterfaceStyle` меняем `setAlternateIconName` на соответствующий вариант.
  - `.light` / `.dark` — фиксированная иконка независимо от системной темы.

---

## Features

### 1. Wishlists

- **Создать** — `+ Новый список` на главном экране, откроется sheet с полями: имя, обложка (камера/галерея/эмодзи/дефолт mesh)
- **Редактировать** — из меню "⋯" внутри вишлиста → «Переименовать», «Сменить обложку»
- **Удалить** — из меню "⋯" → «Удалить список» (red destructive confirmation). Если владелец удаляет общий — все participants теряют доступ.
- **Покинуть** (для participant, не owner) — из меню "⋯" → «Покинуть список». Удаляется только у него, остальные не трогаются.

### 2. Items

- **Создать** — плавающая кнопка `+ Новое желание` внизу экрана вишлиста. Sheet с полями (см. Add Item Flow).
- **Редактировать** — тап → detail → «Изменить». Или long-press → context menu → «Изменить».
- **Удалить** — свайп влево на айтеме → «Удалить» (red), или context menu.
- **Архивировать** — свайп влево → «В архив» (blue, primary swipe action). Или context menu.

### 3. Tier & sort order

**Tier (важность)** — качественная оценка, 3 уровня:
- `must` — 🔥 Обязательно
- `maybe` — 🤔 Пока думаю (default)
- `idea` — 💭 Просто идея

**Manual sort order внутри tier** — поле `sortIndex: Double`. Новые айтемы добавляются в конец своей tier-группы (max(sortIndex) + 1000). Drag-reorder в списке пересчитывает `sortIndex` как midpoint между соседями. Если значения сблизились к limiter — ребалансируем всю tier (пересчёт 1000, 2000, 3000...).

**Сортировки в экране вишлиста:**
- По важности (default) — группировка по tier + manual sort внутри
- По дате добавления
- По дате изменения
- По цене (asc/desc; без цены — в конец)
- По названию (A-Z)

**Фильтры:**
- Скрыть tier `idea` (режим «серьёзный список»)

### 4. Probation (испытательный срок)

- Поле `probationEndAt` у айтема. Если `nil` — срок не активен.
- Визуально: в списке бейдж `⏳ N дней` под именем айтема.
- По истечении: бейдж снимается (автоматически на клиенте при очередном открытии), айтем становится обычным. Тихий переход.
- Опц. push-уведомление «Айтем X прошёл испытательный срок» — если включён toggle `notifyOnProbationEnd`.
- Включается при создании/редактировании: toggle «Испытательный срок» + подстраиваемая длительность (префилл из settings).
- Дефолт в settings: выключен; длительность — 30 дней.

### 5. Archive (soft delete)

- Поле `isArchived: Bool` у айтема.
- Активные айтемы — с фильтром `isArchived = false`.
- Архив — отдельный экран, доступ из меню вишлиста "⋯" → «Архив (N)» (пункт появляется **только если архив непустой**).
- В архиве: восстановить (убрать `isArchived` флаг) или удалить навсегда (red).
- Архивация **не** удаляет айтем — cloud-sync сохраняет его.

### 6. Sharing (CKShare + QR)

- Владелец → меню "⋯" → «Поделиться» или свайп по вишлисту → «Поделиться».
- Sheet с выбором роли (Редактор / Только просмотр) и TTL (15м / 1ч / 24ч / 7д / Без срока).
- Генерируется `CKShare` с `publicPermission = .readWrite` (или `.readOnly`), `participantPermission = .none` до accept.
- URL из `CKShare.url` кодируется в QR-картинку (iOS `CIFilter.qrCodeGenerator`).
- Кнопка «Поделиться QR…» — iOS Share Sheet с QR-картинкой (юзер отправляет в Telegram / iMessage / AirDrop).
- Timer: по истечении TTL приложение ротирует `CKShare` (deletes+recreates → старый URL невалиден). Existing participants сохраняют доступ (Apple persists their accept).
- Revoke вручную — кнопка «Отменить приглашение».
- Participant'ы управляются на отдельном экране «Участники» — список аватаров + роль + кнопки «Сменить роль» и «Удалить».

**Ограничение TTL:** ротация работает пока приложение запущено (или через `BGAppRefreshTask`). Если юзер не открывает приложение, старые ссылки могут пережить свой TTL на клиентском таймере. Mitigation: проверка `expiresAt` при любом открытии приложения — если просрочен, ротируем сразу.

### 7. Smart URL support (LinkPresentation)

- Поле «Ссылка» в форме создания айтема.
- После вставки URL (detect paste or on `onEditingChanged`): `LPMetadataProvider.startFetchingMetadata(for: URL)`.
- Результат `LPLinkMetadata` кэшируется как `Data` в `item.linkMetadataData`.
- Автозаполнение: title → name, imageProvider → coverImageData (если ещё не установлен юзером). Price — только если есть в metadata (редко).
- В detail-вьюхе айтема показывается `LPLinkView` под обложкой.
- В списке айтема бейдж `🔗` + домен («wildberries.ru») под названием.
- Кнопка «Открыть в Safari» в detail + в context menu.
- Ограничение: SPA-сайты с тяжёлым JS могут не отдать meta. В таком случае автозаполнение не срабатывает, юзер пишет руками, URL всё равно сохраняется.

### 8. Share Extension

Отдельный target в Xcode project. iOS показывает `I Wish` в Share Sheet при шеринге URL из любого приложения.

Flow:
1. Юзер в Safari на товаре → `Share` → `I Wish`
2. Extension показывает мини-popover: список вишлистов (картинка + имя) + выбор важности
3. Тап по вишлисту → айтем создаётся с URL и автозаполненными данными (LinkPresentation работает и в extension)
4. Extension закрывается, айтем появляется в основном приложении при следующем открытии

**Tech: shared storage между main app и extension через App Group.**

- App Group ID: `group.com.rugyron.iwish` (placeholder — финальный согласуется с bundle ID)
- SwiftData `ModelContainer` инициализируется с `URL` внутри App Group container (`FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`), а не с дефолтным app sandbox path.
- Both targets (main app + extension) указывают одинаковый App Group entitlement и используют одинаковый schema definition.

**Sync механика:**
- Extension создаёт айтем напрямую в SwiftData (App Group хранилище) — мгновенная запись.
- CloudKit sync **не запускается из extension** (extensions ограничены по lifecycle и background-доступу). Запись остаётся локальной до:
  - Юзер открывает основное приложение → SwiftData-CloudKit mirror подхватывает delta при `applicationDidBecomeActive`.
  - Либо `BGAppRefreshTask` зашёлся (если background refresh разрешён) → принудительный sync через `CKContainer.privateCloudDatabase.save`.
- Это «eventually-consistent» поведение — приемлемо: айтем виден в основном приложении сразу при следующем открытии, а в облаке — после первого sync-окна. Конфликтов не возникает (extension только пишет новое, не редактирует существующее).

**LinkPresentation в extension:** работает, но extension memory limit ~120MB — большие preview-картинки могут не загрузиться. Fallback: сохраняем URL без metadata, main app дотягивает metadata при следующем открытии.

### 9. Onboarding

Показывается при первом запуске (`hasCompletedOnboarding == false`).

4 экрана (horizontal paging):
1. **Welcome** — «I Wish — твой приватный дневник желаний» + иллюстрация (mesh gradient)
2. **Три уровня важности** — объяснение 🔥/🤔/💭 + визуал
3. **Поделись списком** — QR-код + объяснение ролей (Редактор / Только просмотр)
4. **Из Safari в один тап** — скриншот Share Sheet в Safari с подсветкой `I Wish` icon, объяснение добавления через Share Extension

Последний экран — кнопка «Начать». Ставит `hasCompletedOnboarding = true`.

---

## UX Screens

### 1. Home — Каталог вишлистов

- **Заголовок:** «Желания», subtitle «N списков · M желаний»
- **Layout:** вертикальный список больших карточек (один столбец). Каждая карточка: 60px обложка слева, имя, subtitle («N желаний» + «общий с ...» если shared), счётчик tier-бейджей справа (🔥 3 · 🤔 7).
- **Плавающая кнопка** снизу: «＋ Новый список» (стекло, Liquid Glass)
- **Настройки** — иконка `⚙︎` вверху справа

### 2. Wishlist detail

- **Nav bar:** ‹ Желания (left), ⋯ и ↑ (right)
- **Title:** большой, имя вишлиста
- **Subtitle:** «N желаний · общий с X»
- **Чипы сортировки:** 🔥 По важности / 📅 / 💰 / 🔤 / (фильтры)
- **Секции tier:** header «🔥 Обязательно» + сумма по группе («119 980 ₽ · 3») справа
- **Строки айтемов (компактные):** 40px обложка · имя + бейджи (🔗 / ⏳ N) + описание · цена справа
- **Floating button:** «＋ Новое желание»
- **Long-press на айтеме** — context menu: Открыть в Safari / Изменить важность → / Изменить / Архив / Удалить
- **Swipe left:** Архив (blue) / Удалить (red)

### 3. Item detail

- Обложка (full-width, aspect ratio 1:1 или 4:3)
- Название (large title)
- Tier chip
- Rich link preview (`LPLinkView`) — если есть URL
- Описание
- Цена
- Испытательный срок status (если активен)
- Кнопки: «Открыть в магазине» (если URL), «Изменить», «Архив», «Удалить»

### 4. Add Item sheet

Form (iOS `Form` с `insetGrouped` стилем):
- **Ссылка** (опц.) — поле URL с live-парсингом и rich preview после вставки
- **Название** — обязательно
- **Обложка** — тап открывает action sheet: «Камера / Галерея / Эмодзи / Оставить автоматическую»
- **Важность** — segmented control 🔥 / 🤔 / 💭 (default 🤔)
- **Цена** — number + currency picker
- **Описание** — опц.
- **Испытательный срок** — toggle + duration (из settings, можно переопределить)
- Кнопки: `Отмена` / `Готово`

### 5. Settings

iOS `Form`-style, секции:
- **Внешний вид**
  - Тема (светлая / тёмная / системная)
  - Иконка приложения (Авто / Светлая / Тёмная) — «Авто» переключает иконку под системную тему
- **Желания**
  - Валюта по умолчанию (RUB / USD)
  - Испытательный срок по умолчанию (toggle + длительность)
  - Уведомлять о конце испытательного срока (toggle) — *при включении запрашивает push permission через системный диалог. Если юзер отказал — возвращает в off с подсказкой «Разреши уведомления в Настройках iOS»*
- **Приглашения**
  - Срок действия по умолчанию (15м / 1ч / 24ч / 7д / Без срока)
- **О приложении**
  - Версия
  - Политика приватности (опц. ссылка)

### 6. Share flow

Модалка с вкладками / сегментами:
- QR-код большой по центру
- Чипы с TTL (выбран текущий, можно сменить — пересоздаёт share)
- Роль: Редактор / Только просмотр
- Кнопка «Поделиться…» — iOS Share Sheet с QR-картинкой
- Кнопка «Отменить приглашение» (red)
- Под QR: «Действует до HH:MM»

### 7. Participants

- Список аватаров + имён (из `CKShare.Participant` metadata)
- Кнопки напротив каждого: «Сменить роль» / «Удалить»
- Владелец первым, с короной
- Ты — с пометкой «(ты)»

### 8. Archive

- Доступ из меню вишлиста «⋯» → «Архив (N)» (пункт появляется только если архив непустой)
- Список архивированных айтемов, компактный
- Свайп левый: «Восстановить» (blue primary) / «Удалить навсегда» (red)
- Если архив пуст после восстановления/удаления последнего — закрываем экран

---

## Visual Style

- **Стиль:** iOS 26 Liquid Glass, Pure Apple (нейтральный грей + системный синий/indigo акцент)
- **Темы:** светлая / тёмная / системная, переключатель в настройках
- **Все карточки, sheets, плавающие кнопки** — `.ultraThinMaterial` / `.regularMaterial` с blur
- **Dynamic Type** — поддерживаем, тесты на больших шрифтах
- **SF Symbols** — везде для системных иконок
- **Haptics** — tap на tier chip, успешное создание, drag-reorder commit
- **Accent colors:** `.accentColor = .blue` (system), специальные — `.orange` для 🔥, `.green` для success

### Default cover (mesh gradient)

Генеративно по `item.id`:
- Хэш UUID → seed
- Выбираем 2-3 цвета из палитры (8-12 paired палитр — тёплые, холодные, фиолетовые, зелёные)
- Рендерим как `MeshGradient` (SwiftUI iOS 17+) или fallback `LinearGradient` с blur-overlay

Замена:
- Фото — `PhotosPicker` (галерея) или `UIImagePickerController` (камера)
- Эмодзи — custom picker (системного нет, надо сделать — TextField с `keyboardType: .default` и фильтр на эмодзи, или Composable emoji picker библиотеку)

### Cover image storage

- Юзерские фото сжимаются до **JPEG quality 0.7, max edge 1024px** перед сохранением — целевой размер ≤ 500KB.
- Хранятся inline в `coverImageData: Data?`, а не как `CKAsset`. Причина: `CKRecord.encryptedValues` шифрует `Data`-поля прозрачно, но **НЕ применяется к `CKAsset` blob-storage** (CKAsset хранится отдельно от записи нешифрованным). Inline `Data` гарантирует zero-knowledge на картинки.
- CloudKit лимит на запись — 1MB; с компрессией укладываемся с большим запасом, остальное (текст, metadata) — десятки KB.
- Если фото >500KB после компрессии (редко) — повторное сжатие до qualиty 0.5 либо warning юзеру.

---

## Non-Goals (Out of Scope v1)

- **Web версия** — только iOS 26+
- **Android** — CloudKit только Apple
- **Auto price update** — не парсим магазины
- **Multiple URLs per item** — одна ссылка
- **Comments/chat в shared вишлистах** — не нужно
- **Notifications beyond probation end** — никаких маркетинговых/engagement push'ей
- **Analytics / Crashlytics** — ничего не собираем (приватность above all)
- **In-app purchases / subscriptions** — бесплатно
- **Text-codes for sharing** — только QR
- **Public CloudKit DB** — не используем
- **Position picker при создании айтема** — убрали ради скорости; айтем в конец tier, drag-reorder для перестановки

---

## Open Questions / Deferred

- **App logo / icon design** — пользователь обещал передать позднее, пока placeholder
- **Alternate icons (светлая / тёмная)** — будут подготовлены после финального логотипа
- **Точный список цветовых палитр** для generative mesh — подберём на этапе полировки UI
- **Bundle ID** — `com.rugyron.iwish` как placeholder, уточнить при публикации
- **iCloud container ID** — `iCloud.com.rugyron.iwish` или другое, по Apple Developer account
- **App Store copy** — описание, скриншоты, keywords — закроем перед релизом

---

## Testing Strategy

- **SwiftData модели** — unit тесты: CRUD, sort-index rebalancing, tier transitions, probation expiry logic
- **CloudKit sync** — integration тесты с `CKContainer` мок или простые smoke-тесты на девайсе с разными iCloud аккаунтами (участники)
- **LinkPresentation** — тесты на реальных URL (WB, Ozon, Apple, Amazon) — smoke, не автоматизация
- **UI** — snapshot tests на ключевые экраны через Xcode Previews и `swift-snapshot-testing`
- **Share Extension** — мануальное тестирование на реальных устройствах

---

## Milestones (для писания плана)

Грубая разбивка, детальный план — в отдельном документе через `writing-plans`:

1. **M0 — Project scaffolding** — пакеты, target structure, CloudKit container, SwiftData schema
2. **M1 — Local CRUD** — создание/просмотр/редактирование вишлистов и айтемов, локально (SwiftData only)
3. **M2 — Cloud sync** — CloudKit mirror, encryptedValues
4. **M3 — Visual layer** — Liquid Glass styling, mesh gradient defaults, темы
5. **M4 — Tier & sort** — drag-reorder, sort index logic, tier-группы, сортировки/фильтры
6. **M5 — Probation & archive** — логика сроков, архивация, expire-scan
7. **M6 — Smart URLs** — LinkPresentation интеграция, rich preview, paste autofill
8. **M7 — Sharing (CKShare)** — QR, Share Sheet, TTL ротация, participants UI, роли
9. **M8 — Share Extension** — Xcode extension target, App Groups, создание айтема из Safari
10. **M9 — Onboarding** — 4 экрана, first-launch flow
11. **M10 — Settings polish** — theme switcher, alternate icons, все тогглы, iCloud gate
12. **M11 — QA, polish, App Store prep** — тесты на реальных девайсах, иконки, финальные скриншоты

---

## Glossary (friendly copy)

В UI никогда не пишем технический жаргон. Вот словарь для локализации:

| Технично | Для UI |
|----------|--------|
| CloudKit | (не упоминаем) |
| CKShare | (не упоминаем) |
| Revoke invite | Отменить приглашение |
| Invite TTL | Срок действия приглашения |
| Probation period | Испытательный срок |
| Tier | Важность |
| Owner | Владелец |
| Participant | Участник |
| Read-only role | Только просмотр |
| Read-write role | Редактор |
| Archive | Архив |
| Soft-delete | В архив |
| Hard-delete | Удалить навсегда |
| Encryption | (не упоминаем; можно сказать «Твои данные защищены, даже мы их не видим») |
| Link metadata | Информация со ссылки |
