# IWish v1.1 — hotfix + features design

**Дата:** 2026-05-08
**Цель:** Один билд v1.1 со всеми накопленными правками + миграция без потери данных + Force Update инфра + iPad адаптация.
**Контекст:** v1.0 (build 4) апрувнут и в App Store. Юзеры — Влад + друзья. После v1.1 release Влад попросит всех обновиться.
**Выбран однофазный путь** (не v1.0.1 → v1.1).

---

## 0. Сводка решений

| Решение | Значение |
|---------|----------|
| Roadmap | Один билд v1.1 |
| Rate limiter | 300/мин + debounce 500ms |
| Card corner radius | 8pt |
| iPad | Полноценный (sidebar/master-detail, обе ориентации) |
| Имя пользователя | Gate: no name → no app |
| Цена-диапазон | Toggle "Точная / Диапазон", на карточке показ только "до Y", в детальном "X — Y" |
| Force update | Hard min_supported_build + soft recommended (toast) |
| Migration safety | preserve-unknown-keys в updateItem + one-time backfill при первом старте v1.1 |

---

## 1. Migration strategy (раздел читать первым)

### 1.1. Принципы

1. **Additive-only**: новые поля Optional, старые не трогаем.
2. **Lightweight SwiftData migration**: автоматическая, без MigrationPlan (Optional fields не требуют ручной).
3. **Preserve unknown keys** в всех `updateXxx` методах: GET → decrypt → merge changes в существующий dict → re-encrypt.
4. **One-time backfill** при первом запуске v1.1: маркер `iwish_v11_backfill_done` в UserDefaults.

### 1.2. Field-by-field аудит payload (bugs)

Текущее состояние SwiftData ↔ Firestore encryptedPayload:

**Item:**
| SwiftData field | В payload? | Действие |
|----------------|-----------|----------|
| name | ✅ | — |
| descriptionText | ❌ | **Добавить ключ "description"** (#14) |
| coverImageData | ❌ | **Добавить ключ "coverImageData"** (base64) |
| coverEmoji | ✅ | — |
| priceValue | ✅ | — |
| priceMaxValue (новый) | — | **Добавить ключ "priceMax"** (#8) |
| currency | ✅ | — |
| url | ✅ | — |
| linkMetadataData | ❌ | **Добавить ключ "linkMeta"** (base64) |
| tierRaw | ✅ | — |
| sortIndex | ✅ | — |
| probationEndAt | ❌ | **Добавить ключ "probationEndAt"** (ISO8601) |
| isArchived | ✅ | — |
| addedByUID | ✅ | — |
| addedByName | ✅ | — |

**Wishlist (personal):**
| SwiftData | В payload? | Действие |
|-----------|-----------|----------|
| name, coverEmoji, coverImageData | ✅ | — |
| gradientSeed | plaintext field | сохраняем для legacy fallback |
| gradientHue (новый) | — | **Добавить plaintext field "gradientHue" Double?** (#7) |

**Wishlist (shared):**
| SwiftData / inferred | В payload? | Действие |
|---------------------|-----------|----------|
| name, coverEmoji, coverImageData, ownerName | ✅ | — |
| gradientHue (новый) | — | Добавить plaintext field |

### 1.3. preserve-unknown-keys паттерн

Сейчас `updateXxx` методы строят payload полностью из переданных параметров и шифруют. Если callsite забыл поле — оно теряется. Текущий FIXME в `FirestoreService:357` это подтверждает.

**Новый подход для всех `update*Item` и `update*Wishlist`:**

```swift
func updateSharedItem(...) async throws {
    // 1. GET существующий документ
    let existingDoc = try await request("GET", path: "shared_wishlists/\(wishlistID)/items/\(itemID)")
    let existingPayload: [String: Any]
    if let fields = existingDoc["fields"] as? [String: Any],
       let encryptedData = parseFields(fields)["encryptedPayload"] as? Data,
       let decrypted = try? EncryptionService.decrypt(encryptedData, using: key) {
        existingPayload = decrypted
    } else {
        existingPayload = [:]  // нет существующего — пишем с нуля
    }

    // 2. Merge: наши изменения накладываем на существующий dict
    var merged = existingPayload
    let updates: [String: Any?] = [
        "name": name,
        "tier": tier,
        "price": price,
        "priceMax": priceMax,
        "currency": currency,
        "url": url,
        "coverEmoji": emoji,
        "coverImageData": coverImageData,
        "linkMeta": linkMetadataData,
        "description": descriptionText,
        "probationEndAt": probationEndAt?.iso8601String,
        "addedByUID": addedByUID,
        "addedByName": addedByName
    ]
    for (k, v) in updates {
        if let v {
            if let d = v as? Data {
                merged[k] = d.base64EncodedString()
            } else {
                merged[k] = v
            }
        } else {
            merged.removeValue(forKey: k)  // explicitly nil → стираем
        }
    }

    // 3. Encrypt + PATCH
    let encrypted = try EncryptionService.encrypt(merged, using: key)
    // ...
}
```

**Стоимость:** +1 GET на каждый updateItem (~10-50ms). Для шаринг-сценария это ОК — операции редкие. Polling не использует updateItem.

**Защита:** наш v1.1 клиент не теряет НИКАКИЕ ключи payload (включая будущие, добавленные после v1.1).

### 1.4. One-time backfill при первом старте v1.1

В `IWishApp.init()` после `FirebaseApp.configure()`:

```swift
private func runMigrationsIfNeeded() {
    let key = "iwish_v11_backfill_done"
    guard !UserDefaults.standard.bool(forKey: key) else { return }

    Task { @MainActor in
        let context = container.mainContext
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []

        for item in items {
            // Пропуск если все поля уже синхронизированы (для items без missing data)
            let needsBackfill = item.descriptionText?.isEmpty == false
                || item.coverImageData != nil
                || item.linkMetadataData != nil
                || item.probationEndAt != nil
            guard needsBackfill else { continue }
            guard let wishlist = item.wishlist else { continue }

            // updateItem уже использует preserve-unknown-keys паттерн — read existing payload,
            // merge все наши локальные значения (включая описание), re-encrypt.
            // Если сеть отвалилась — try? проглотит, повторим в следующий старт (маркер не выставляем).
            try? await AppServices.shared.data?.updateItem(
                id: item.id.uuidString,
                wishlistID: wishlist.id.uuidString,
                name: item.name,
                tier: item.tier,
                price: item.price,
                priceMax: item.priceMaxValue,
                currency: item.currency,
                url: item.url,
                emoji: item.coverEmoji,
                sortIndex: item.sortIndex,
                isArchived: item.isArchived,
                descriptionText: item.descriptionText,
                coverImageData: item.coverImageData,
                linkMetadataData: item.linkMetadataData,
                probationEndAt: item.probationEndAt
            )
        }

        // Маркер выставляем только если backfill прошёл целиком.
        // Если внутри был throw — try? проглотил, маркер НЕ выставляется → повтор при следующем старте.
        UserDefaults.standard.set(true, forKey: key)
    }
}
```

**Идемпотентно:** updateItem с теми же значениями = no-op в данных (только updatedAt меняется).

**Не блокирует UI:** запускается асинхронно, юзер видит главный экран сразу. Backfill идёт в фоне.

### 1.5. SwiftData migration

Добавляем 2 Optional-поля:
- `Item.priceMaxValue: Double?` (default nil)
- `Wishlist.gradientHue: Double?` (default nil)

SwiftData делает lightweight migration автоматически (Optional с default не требует ручного MigrationPlan).

Existing данные:
- `Item.priceValue: Double?` — остаётся как было.
- `Wishlist.gradientSeed: Int` — остаётся, используется как fallback.

### 1.6. User-side risk acceptance

После релиза v1.1 риск:
- Старые v1.0 клиенты могут перезаписать payload без новых ключей при write в shared wishlists.
- **Защита**: Влад просит всех обновиться. До общего обновления — никто не редактирует shared wishlists (read ок).
- Force Update в v1.1 защитит **будущие** релизы (v1.2+) от старых клиентов.

---

## 2. По правкам

### 2.1. Rate limiter (#1)

**Файл:** `Services/InputLimits.swift`, `Services/FirestoreService.swift`

```swift
// InputLimits.swift
static let maxFirestoreRequestsPerMinute = 300  // было 60

// DataService.swift — debounce при последовательных правках одного item
private var pendingItemUpdates: [String: Task<Void, Error>] = [:]

func updateItem(...) async throws {
    let itemKey = id

    // Cancel pending для того же item
    pendingItemUpdates[itemKey]?.cancel()

    let task = Task {
        try await Task.sleep(for: .milliseconds(500))
        try Task.checkCancellation()
        try await performUpdateItem(...)
    }
    pendingItemUpdates[itemKey] = task
    try await task.value
}
```

**Альтернатива (проще)**: оставить updateItem без debounce, но повысить cap до 300. Если burst > 300 — это уже патология, юзер увидит rateLimited.

**Решение**: только повысить cap до 300, debounce **отложить** на v1.2 если будет проблема. Не усложнять.

### 2.2. Имя пользователя как gate (#2, #5, #12, #13)

**Файлы:** `Services/AuthService.swift`, `Views/SignInWithAppleSheet.swift`, `Views/RootView.swift`, `IWishApp.swift`

**AuthService изменения:**
1. Удалить `?? "Пользователь"` из строки 186 — если все 4 источника пусты, `userName` остаётся `nil`.
2. Добавить новое состояние: `var requiresNameRecovery: Bool` — true если:
   - Юзер залогинен (`_isAppleSignedIn == true`)
   - НО `userName == nil` ИЛИ `userName == "Пользователь"` (старый мусор)
3. В `verifyAndRestore`: если `userName == "Пользователь"` → стереть из Keychain, выставить nil, выставить `requiresNameRecovery = true`.
4. В `handleSignInWithApple`: если `resolvedName == nil` после всех 4 fallback → НЕ вызывать `KeychainService.saveUserName(...)` с мусором, выставить `requiresNameRecovery = true` и не считать sign-in успешным.

**RootView изменения:**
- Если `services.auth.requiresNameRecovery == true` → показать `NameRecoveryView` (новый sheet вместо HomeView).

**Новый view: `Views/NameRecoveryView.swift`:**
- Заголовок: "Не удалось получить ваше имя"
- Текст: "Apple Sign In не передал имя при входе. Чтобы восстановить — выйдите и войдите снова. Возможно потребуется удалить I Wish из списка приложений Sign In with Apple в настройках iPhone."
- Кнопки: "Выйти" (signOut + перевод в SignInScreen) и "Открыть настройки Apple ID" (`UIApplication.shared.open(URL(string: "App-Prefs:APPLE_ACCOUNT")!)`).

**Почему "Apple ID" в Settings раньше работал:** код был `userName ?? "Apple ID"` — но `userName` стал ненильным "Пользователь", fallback не срабатывал. После фикса userName реально nil не пройдёт через gate, в Settings можно оставить "Apple ID" как ультра-fallback (на случай если gate проболтает).

**Имена member в memberships (для #5/#12 enhanced):**

`FirestoreService.joinWishlist` — добавить поле `userName`:
```swift
func joinWishlist(wishlistID: String, userUID: String, userName: String, role: String, canInvite: Bool = false) async throws {
    let fields = toFields([
        "wishlistID": wishlistID,
        "userUID": userUID,
        "userName": userName,  // NEW — plaintext, owner и так знает relation между UID и user
        "role": role,
        ...
    ])
}
```

Backfill: при первом старте v1.1, после name gate (имя гарантированно есть) — `updateMyMembershipsName(userName)` пройдёт по всем моим memberships и `PATCH userName` — owner потом увидит реальное имя.

`fetchSharedWishlist`: `members` теперь `[(userUID: String, role: String, userName: String?)]`.

`ParticipantsView` обновляется: для не-self member'а — `member.userName ?? "Участник"`.

**Migration backward**: старые memberships без userName → fallback "Участник" остаётся. После backfill — у всех Влад'ов будет имя.

### 2.3. Keyboard simplify (#3)

**Файлы:** `Views/AddItemSheet.swift`, `EditItemSheet.swift`, `AddWishlistSheet.swift`, `EditWishlistSheet.swift`

В каждом из 4 sheet'ов:
1. Удалить `ToolbarItemGroup(placement: .keyboard) { ... }` (кнопку chevron вниз).
2. `.scrollDismissesKeyboard(.interactively)` уже стоит — оставить.
3. Добавить tap-to-dismiss на форму:

```swift
Form { ... }
    .contentShape(Rectangle())
    .onTapGesture {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
```

Tap-to-dismiss работает на пустом пространстве формы. Tap внутри input не блокируется (TextField перехватывает touch первым).

### 2.4. Decimal display fix (#4)

**Файл:** `Views/EditItemSheet.swift:119`

```swift
// БЫЛО
priceString = item.price.map { "\($0)" } ?? ""

// СТАЛО
priceString = item.price.map { String(Int($0)) } ?? ""
```

Также в `AddItemSheet.swift:307` и `EditItemSheet.swift:145`:

```swift
private func parsePrice(_ string: String) -> Double? {
    let trimmed = string.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    // Принимаем только целые
    return Int(trimmed).map(Double.init)
}
```

Все display formatters уже Int-only (`maximumFractionDigits = 0`). Единственный bug — input prefill в EditItemSheet.

**Numeric pad layout**: оставить как есть (iOS HIG, не меняем).

### 2.5. Tier picker emoji always (#6)

**Файл:** `Views/WishlistDetailView.swift:825-857`

```swift
Menu {
    ForEach(ItemTier.allCases) { tier in
        Button { ... } label: {
            // БЫЛО: разная отрисовка для выбранной vs не-выбранной
            // СТАЛО: эмодзи всегда + checkmark отдельно
            HStack {
                Text("\(tier.emoji) \(tier.label)")
                if item.tier == tier {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
} label: { ... }
```

В SwiftUI Menu Button с `Text` или `HStack` рендерится корректно. Альтернатива — `Label` со systemImage:

```swift
Label("\(tier.emoji) \(tier.label)", systemImage: item.tier == tier ? "checkmark" : "circle")
```

Но "circle" для не-выбранных — лишний шум. Лучше первый вариант.

### 2.6. Gradient hue picker (#7)

**Файлы:** `Models/Wishlist.swift`, `Services/DefaultCoverGenerator.swift`, `Views/Components/GradientHuePicker.swift` (новый), `Views/EditWishlistSheet.swift`, `Views/AddWishlistSheet.swift`, `Services/FirestoreService.swift`, `Services/DataService.swift`

**Modeling:**
- `Wishlist.gradientHue: Double?` (новое Optional, 0...1)
- Если `gradientHue != nil` → используем для генерации (HSB градиент с hue, насыщенностью 0.7, brightness 0.85)
- Иначе → fallback на старый `gradientSeed` + 24 палитры

**DefaultCoverGenerator extensions:**

```swift
static func colors(forHue hue: Double) -> [Color] {
    // 3 цвета вокруг базового hue, ±0.08 для богатства градиента
    let base = hue
    let h1 = (base - 0.08).truncatingRemainder(dividingBy: 1)
    let h2 = base
    let h3 = (base + 0.08).truncatingRemainder(dividingBy: 1)
    return [
        Color(hue: h1 < 0 ? h1 + 1 : h1, saturation: 0.75, brightness: 0.85),
        Color(hue: h2,                    saturation: 0.65, brightness: 0.90),
        Color(hue: h3 > 1 ? h3 - 1 : h3, saturation: 0.70, brightness: 0.80)
    ]
}

/// Резолвер: hue если есть, иначе palette по seed
static func colors(for wishlist: Wishlist) -> [Color] {
    if let hue = wishlist.gradientHue {
        return colors(forHue: hue)
    }
    return colors(forSeed: wishlist.gradientSeed)
}
```

**Picker view (`GradientHuePicker.swift`):**

```swift
struct GradientHuePicker: View {
    @Binding var hue: Double  // 0...1

    var body: some View {
        VStack(spacing: 16) {
            // Превью градиента — анимирует hue
            RoundedRectangle(cornerRadius: 16)
                .fill(MeshGradient(...colors from hue...))
                .frame(height: 120)
                .animation(.easeOut(duration: 0.15), value: hue)

            // Радужный слайдер
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Фон — горизонтальная радуга
                    LinearGradient(
                        colors: stride(from: 0.0, through: 1.0, by: 0.05).map {
                            Color(hue: $0, saturation: 0.8, brightness: 0.9)
                        },
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(height: 32)
                    .clipShape(Capsule())

                    // Thumb
                    Circle()
                        .fill(Color(hue: hue, saturation: 0.8, brightness: 0.95))
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                        .frame(width: 32, height: 32)
                        .offset(x: max(0, min(geo.size.width - 32, geo.size.width * hue - 16)))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let x = max(0, min(geo.size.width, value.location.x))
                                    hue = x / geo.size.width
                                }
                        )
                }
            }
            .frame(height: 32)
        }
    }
}
```

**Интеграция в EditWishlistSheet/AddWishlistSheet:**
- Показывать GradientHuePicker **только если нет фотографии** (coverImageData == nil).
- Если есть фото — пикер скрыт, фото — главное.
- Также если эмодзи задан — пикер виден (эмодзи поверх градиента).

В sheet:
```swift
@State private var gradientHue: Double = wishlist?.gradientHue ?? Double.random(in: 0...1)

// В Form:
if coverImageData == nil {
    Section("Цвет обложки") {
        GradientHuePicker(hue: $gradientHue)
    }
}
```

Сохранение: при save передаётся в `updateWishlist` / `createWishlist`.

**Firestore сторона:**
- `gradientHue: Double?` plaintext field в documents (рядом с gradientSeed).
- Создание/обновление wishlist'а — добавить параметр `gradientHue` в createPersonalWishlist, updatePersonalWishlist, createSharedWishlist, updateSharedWishlist.
- Чтение — добавить в `fetchPersonalWishlists`, `fetchSharedWishlist` парсинг.

### 2.7. Range pricing (#8)

**Files:** `Models/Item.swift`, `Views/AddItemSheet.swift`, `Views/EditItemSheet.swift`, `Views/WishlistDetailView.swift` (карточка + sum), `Views/ItemDetailSheet.swift` (детальный экран), payload backend, Settings.

**Item изменения:**
```swift
@Model
final class Item {
    // ... existing
    var priceMaxValue: Double?  // NEW — если задан, item имеет диапазон

    var price: Double? { /* как было */ }
    var priceMax: Double? {
        get { priceMaxValue }
        set { priceMaxValue = newValue }
    }

    /// Удобный enum для UI
    enum PriceMode {
        case none                        // оба nil
        case exact(Double)               // только priceValue
        case range(min: Double, max: Double)  // оба
    }

    var priceMode: PriceMode {
        switch (priceValue, priceMaxValue) {
        case (nil, nil): return .none
        case (let p?, nil): return .exact(p)
        case (let p?, let m?): return .range(min: p, max: m)
        case (nil, let m?): return .range(min: 0, max: m)  // legacy guard
        }
    }
}
```

**Add/Edit Sheet UI:**

```swift
@State private var priceMode: PriceModeUI = .exact  // .exact / .range
@State private var priceMinString = ""
@State private var priceMaxString = ""

// в Form:
Section("Цена") {
    Picker("Тип", selection: $priceMode) {
        Text("Точная").tag(PriceModeUI.exact)
        Text("Диапазон").tag(PriceModeUI.range)
    }
    .pickerStyle(.segmented)

    if priceMode == .exact {
        HStack {
            TextField("0", text: $priceMinString).keyboardType(.numberPad)
            CurrencyPicker(selection: $currency)
        }
    } else {
        HStack {
            TextField("От", text: $priceMinString).keyboardType(.numberPad)
            Text("—")
            TextField("До", text: $priceMaxString).keyboardType(.numberPad)
            CurrencyPicker(selection: $currency)
        }
    }
}
```

При save:
```swift
let price: Double? = parsePrice(priceMinString)
let priceMax: Double? = priceMode == .range ? parsePrice(priceMaxString) : nil
```

**Карточка в WishlistDetailView (itemRow):**
```swift
private func priceText(for item: Item) -> String? {
    switch item.priceMode {
    case .none: return nil
    case .exact(let p): return formatPrice(p, currency: item.currency)
    case .range(_, let max):
        // По требованию: на карточке мало места — показываем только "до Y"
        return "до \(formatPrice(max, currency: item.currency))"
    }
}
```

**ItemDetailSheet (полный):**
```swift
private var priceFullText: String? {
    switch item.priceMode {
    case .none: return nil
    case .exact(let p): return formatPrice(p, ...)
    case .range(let min, let max):
        return "\(formatPrice(min, ...)) — \(formatPrice(max, ...))"
    }
}
```

**Сумма wishlist'а в обложке:**
- Сейчас: `total = activeItems.compactMap(\.price).reduce(0, +)` → "12 000 ₽".
- После: если есть **хоть один item с диапазоном** — отображать "от Σmin до Σmax".

```swift
private var totalDisplay: String? {
    let items = activeItems
    let hasRange = items.contains { item in
        if case .range = item.priceMode { return true }
        return false
    }

    if hasRange {
        let totalMin = items.compactMap { item -> Double? in
            switch item.priceMode {
            case .none: return nil
            case .exact(let p): return p
            case .range(let min, _): return min
            }
        }.reduce(0, +)
        let totalMax = items.compactMap { item -> Double? in
            switch item.priceMode {
            case .none: return nil
            case .exact(let p): return p
            case .range(_, let max): return max
            }
        }.reduce(0, +)
        return "\(formatPrice(totalMin, ...)) — \(formatPrice(totalMax, ...))"
    } else {
        let total = items.compactMap(\.price).reduce(0, +)
        return total > 0 ? formatPrice(total, ...) : nil
    }
}
```

Аналогично для tier-headers (groupedByTier).

**Сортировка по цене:** сейчас сравнивает `price`. После — сравнивать **min или average**:
- `.exact(p)` → p
- `.range(min, max)` → (min + max) / 2

Простая правка в `sortedItems(by: .price)`.

### 2.8. Bottom safe area (#9)

**Файл:** `Views/HomeView.swift`

Сейчас:
```swift
var body: some View {
    Group { ... }
        .navigationTitle(...)
        .toolbar { ... }
        .overlay(alignment: .bottom) { addButton.padding(.bottom, 24) }
}

// wishlistList:
ScrollView { ... }
    .warmBackground()
```

Проблема: `.warmBackground()` стоит **только** на ScrollView. `.overlay` рисуется поверх Group, в области между ScrollView'ом и safe area может просвечивать чёрный root.

Фикс:
```swift
var body: some View {
    Group { ... }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .warmBackground()  // ← теперь на корне
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(...)
        .toolbar { ... }
        .overlay(alignment: .bottom) {
            addButton.padding(.bottom, 24)
        }
}
```

ВАЖНО: `.ignoresSafeArea(edges: .bottom)` распространяет background на bottom safe area. Toolbar и top safe area не трогаем.

### 2.9. Card corner radius (#10)

**Файл:** `Views/WishlistDetailView.swift` — itemRow `listRowBackground`.

**Решение:** оставить `.insetGrouped` listStyle (как сейчас), снизить corner через custom `listRowBackground` поверх системной ячейки.

Сейчас: `.listRowBackground(Color(.secondarySystemGroupedBackground))` — flat color, рендерится через стандартный inset-grouped (corner ~10pt).

Фикс:
```swift
.listRowBackground(
    RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
)
.listRowSeparator(.hidden)
```

Каждая ячейка получает own RoundedRectangle 8pt поверх стандартного фона insetGrouped. `.listRowSeparator(.hidden)` убирает разделители (карточки визуально отделяются собственным background).

Если визуально между карточками будет мало места — добавим vertical padding к самому `itemRow` content (`.padding(.vertical, 2)` уже есть на строке 607).

**listStyle не меняется** — остаётся insetGrouped.

### 2.10. Settings version caption (#11)

**Файл:** `Views/SettingsView.swift:287-291`

```swift
private var appVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
}
```

Удалить build extraction и скобки.

`openFeedbackMail()` оставить с build (это ушло в письмо разработчику, нужно для дебага).

### 2.11. Description sync (#14) + другие missing fields

См. раздел 1.2 + 1.3 + 1.4.

Конкретно для description:
- Добавить ключ "description" в payload (createSharedItem, createPersonalItem, updateSharedItem, updatePersonalItem).
- Передавать descriptionText из DataService.addItem/updateItem (сейчас не передаётся).
- При decrypt — читать `content["description"] as? String`.
- One-time backfill для existing local descriptions.

То же самое для `coverImageData`, `linkMetadataData`, `probationEndAt`.

### 2.12. iPad адаптация (#15)

**Файлы:** `IWish.xcodeproj/project.pbxproj`, `Views/HomeView.swift`, `Views/WishlistDetailView.swift`, `RootView.swift`, `Views/QRScannerView` (и другие fullscreens).

**Project settings:**
- `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad)
- `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"`
- iPhone оставляем portrait-only.

**RootView — master/detail на iPad landscape:**

Сейчас RootView использует `NavigationStack`. Заменить на `NavigationSplitView` с size class adaptation:

```swift
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            // iPad / iPhone landscape — split
            NavigationSplitView {
                HomeView()
            } detail: {
                Text("Выберите список").foregroundStyle(.secondary)
            }
        } else {
            // iPhone portrait
            NavigationStack {
                HomeView()
            }
        }
    }
}
```

Tap по wishlist в HomeView в split-режиме — пушит WishlistDetailView в detail колонку.

**HomeView grid:**
- iPhone: 2 columns (как сейчас)
- iPad portrait: 3 columns
- iPad landscape: 4 columns

```swift
private var gridColumns: [GridItem] {
    let count: Int
    switch sizeClass {
    case .compact: count = 2
    case .regular:
        // iPad: смотрим ширину контейнера
        count = (UIScreen.main.bounds.width > 1000) ? 4 : 3
    default: count = 2
    }
    return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
}
```

**FullScreenCover'ы (QRScannerView, CameraImagePicker):**
- Сейчас `prefersStatusBarHidden=true`, `prefersHomeIndicatorAutoHidden=true`.
- На iPad оставить, но проверить что system gestures (Dock swipe-up, Control Center) работают. Они работают если view не блокирует edges (deferringSystemGestures).

**iPad-specific UX:**
- Hover states: `.hoverEffect(.lift)` на интерактивных элементах (тайлы, кнопки в menu) — для trackpad/Apple Pencil.
- Larger toolbar items: SwiftUI auto-adapts через `.adaptive`.

**Безопасность жестов:**
- Двойной тап top bar для scroll-to-top — это **system behavior** для ScrollView/List. Работает автоматически если ScrollView правильно встроен в NavigationStack/SplitView.
- Свайп снизу для Dock — system gesture, мы его не блокируем (нет defersSystemGestures на root).

### 2.13. Force update (#16)

**Файлы:** `Services/RemoteConfigService.swift` (новый), `Views/ForceUpdateBlockingView.swift` (новый), `IWishApp.swift`, Package.swift / SPM dependencies.

**Dependency:** добавить `FirebaseRemoteConfig` в SPM (уже есть FirebaseCore + FirebaseAuth, добавить ещё один SDK).

**RemoteConfigService:**

```swift
import FirebaseRemoteConfig

@Observable
@MainActor
final class RemoteConfigService {
    var isLoading = true
    var minSupportedBuild: Int = 0       // 0 = no minimum
    var forceUpdateMessage: String?
    var fetchFailed = false

    private let rc = RemoteConfig.remoteConfig()

    init() {
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 0  // в проде — 3600 (час)
        rc.configSettings = settings
        rc.setDefaults([
            "min_supported_build": 0 as NSNumber,
            "force_update_message": "" as NSString
        ])
    }

    func fetch() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Timeout 5 секунд — не блокируем юзера на отсутствии сети
            let task = Task {
                try await rc.fetchAndActivate()
            }
            let _ = try await withTimeout(seconds: 5) {
                try await task.value
            }

            minSupportedBuild = Int(rc.configValue(forKey: "min_supported_build").numberValue.intValue)
            let msg = rc.configValue(forKey: "force_update_message").stringValue
            forceUpdateMessage = msg.isEmpty ? nil : msg
            fetchFailed = false
        } catch {
            fetchFailed = true
        }
    }

    var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
    }

    var requiresForceUpdate: Bool {
        guard !fetchFailed else { return false }  // нет сети — пускаем
        return currentBuild < minSupportedBuild
    }
}
```

Только hard force update. Soft recommended (toast/баннер) не делаем — Влад решил что это лишний шум.

**ForceUpdateBlockingView:**

```swift
struct ForceUpdateBlockingView: View {
    let message: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Обновите I Wish")
                    .font(.title2.weight(.semibold))
                Text(message ?? "Установлена устаревшая версия. Обновитесь, чтобы продолжить.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Button {
                if let url = URL(string: "https://apps.apple.com/app/id6762267281") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Открыть App Store")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}
```

**Integration в RootView:**

```swift
struct RootView: View {
    @State private var rc = RemoteConfigService()

    var body: some View {
        Group {
            if rc.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background.ignoresSafeArea())
            } else if rc.requiresForceUpdate {
                ForceUpdateBlockingView(message: rc.forceUpdateMessage)
            } else {
                // Обычный flow (с name gate)
                MainContent()
            }
        }
        .task {
            await rc.fetch()
        }
    }
}
```

**Поведение при отсутствии сети:**
- `fetchFailed == true` → пускаем юзера. Не блокируем работу offline.

**Firebase Console setup (Влад делает руками):**
1. Включить Remote Config в Firebase Console.
2. Создать параметры: `min_supported_build` (Number, default 0), `force_update_message` (String, default "").
3. После релиза v1.1 и общего обновления: выставить `min_supported_build = <текущий build v1.1>` чтобы заблокировать v1.0 для **новых** запусков.

---

## 3. Build & submit план

### 3.1. CFBundleShortVersionString → "1.1"

Bump в `IWish.xcodeproj/project.pbxproj`:
- `MARKETING_VERSION = 1.1`
- `CURRENT_PROJECT_VERSION = 5` (был 4)

### 3.2. App Store Connect

1. Создать новую версию **1.1** в ASC (через UI или API).
2. Загрузить build #5 (v1.1) через `xcodebuild archive` + `exportArchive` с `OTHER_CODE_SIGN_FLAGS="--strip-disallowed-xattrs"`.
3. Прицепить build к версии 1.1.
4. **What's New in This Version** (UI-only, не через API):
   ```
   • Полная адаптация под iPad
   • Возможность задать диапазон цены желания
   • Пикер цвета обложки списка
   • Описания желаний теперь синхронизируются между устройствами
   • Множество улучшений: имя пользователя, клавиатура, отображение цен
   ```
5. Submit for review.

### 3.3. Firebase Console (Влад)

После апрува v1.1 в App Store:
- В Firebase Console → Remote Config → выставить `min_supported_build = 5`.
- Это заблокирует v1.0 (build 4) для новых запусков (требует наличия v1.1 у юзера).

### 3.4. User communication (Влад)

Сообщение в чат друзьям:
> "Ребят, обновляйте I Wish в App Store — выкатил большой апдейт. До тех пор пока все не обновитесь — пожалуйста, не редактируйте чужие желания в общих списках, могут потеряться описания и диапазоны цен. Просмотр работает нормально."

---

## 4. Testing plan

### 4.1. Unit-able

- `EncryptionService` round-trip с новыми полями (description, priceMax, coverImageData)
- `Item.priceMode` все 4 кейса
- `DefaultCoverGenerator.colors(forHue:)` диапазон 0-1
- preserve-unknown-keys: payload {a:1, b:2}, update b → must keep a

### 4.2. Manual (на iPhone Влада + iPad)

**iPhone:**
1. Создать new wishlist → создать item с описанием → проверить что description в Firestore (Firebase Console)
2. Существующий item с описанием в SwiftData → запустить v1.1 → проверить backfill через Firebase Console
3. Sign-out → re-sign-in без full name (через Settings → Apple ID → Stop Using → Re-add) → проверить gate
4. Создать диапазон цены → проверить отображение на карточке "до Y" + детальном "X — Y"
5. Сменить градиент через пикер → перезапустить app → проверить сохранение
6. Поменять важность через context menu → проверить что эмодзи виден на выбранной
7. Открыть/закрыть клавиатуру в AddItemSheet, EditItemSheet — без бара, tap-вне закрывает
8. Цена в редактировании item — без ".0"
9. Нижняя safe area — без чёрного
10. Версия в Settings — без билда
11. Carousel участников — реальные имена (после backfill memberships)

**iPad:**
1. Запуск в portrait → 3 column grid
2. Поворот в landscape → 4 column + master/detail
3. Двойной тап top bar → scroll-to-top
4. Свайп снизу для Dock
5. Multitasking (Slide Over) — должно работать
6. QR scanner на iPad — orientation lock не должен мешать

**Migration:**
1. Установить v1.0 (debug build), создать данные с описаниями + картинками
2. Поверх установить v1.1 (debug build) — данные не дропаются
3. Запустить → backfill → проверить через Firebase Console что descriptions появились

**Force update:**
1. В Firebase Console временно выставить `min_supported_build = 99` → запустить app → должен показать ForceUpdateBlockingView
2. Сбросить → перезапустить → главный экран

### 4.3. Apple review-ready check

- Account deletion flow (из v1.0) не должен сломаться. Прогнать сценарий.
- Privacy manifest без изменений (PrivacyInfo.xcprivacy остаётся).
- ITSAppUsesNonExemptEncryption=NO остаётся.

---

## 5. Открытые риски / known limitations

1. **Старые v1.0 клиенты в shared write** — могут перезаписать payload без новых ключей. Mitigation: Влад просит всех обновиться + не редактировать shared до общего обновления.

2. **Firebase Remote Config fetch failure (offline first launch)** — пускаем юзера. Force update начнёт работать когда сеть появится.

3. **iPad полноценная адаптация** — большой scope. Базово сделано в v1.1, но для production-quality могут понадобиться:
   - iPad-specific assets (App Icon iPad, Splash screen iPad)
   - Hover states везде
   - Keyboard shortcuts (⌘N для new wishlist, ⌘W close, etc)
   - Pencil hover
   Эти детали — на v1.2.

4. **Backfill performance** — если у юзера 50+ items с descriptions, backfill = 50+ HTTP запросов при первом старте. Растягиваем на фон, не блокируем UI. Если пол-quota Firestore сжигается — увидим в логах.

5. **`gradientHue` plaintext** — теоретически утечка минорная (видно "юзер выбрал розовый градиент"). Если приватность критична — переместить в encryptedPayload. Пока решено plaintext для простоты polling.

---

## 6. Файлы которые меняются

**Изменения (existing):**
- `Models/Item.swift` — priceMaxValue
- `Models/Wishlist.swift` — gradientHue
- `Services/AuthService.swift` — name gate
- `Services/DataService.swift` — preserve unknown + backfill + новые поля
- `Services/FirestoreService.swift` — preserve unknown + новые поля + memberships userName + rate limit cap
- `Services/InputLimits.swift` — cap 300
- `Services/DefaultCoverGenerator.swift` — colors(forHue:)
- `Views/AddItemSheet.swift` — keyboard, range, decimal
- `Views/EditItemSheet.swift` — keyboard, range, decimal fix
- `Views/AddWishlistSheet.swift` — keyboard, hue picker
- `Views/EditWishlistSheet.swift` — keyboard, hue picker
- `Views/WishlistDetailView.swift` — tier menu emoji, card radius, range display, sum
- `Views/HomeView.swift` — safe area, iPad grid
- `Views/SettingsView.swift` — version caption
- `Views/ParticipantsView.swift` — member.userName из memberships
- `Views/JoinWishlistSheet.swift` — joinWishlist с userName
- `Views/RootView.swift` — split view + force update gate + name gate
- `Views/ItemDetailSheet.swift` — range "X — Y" display
- `Views/Components/WishlistTileView.swift` — gradientHue rendering
- `IWishApp.swift` — runMigrationsIfNeeded + RemoteConfigService init
- `IWish.xcodeproj/project.pbxproj` — TARGETED_DEVICE_FAMILY, orientations, version bump

**Новые файлы:**
- `Views/Components/GradientHuePicker.swift`
- `Views/NameRecoveryView.swift`
- `Views/ForceUpdateBlockingView.swift`
- `Services/RemoteConfigService.swift`

**Tests (минимум):**
- `IWishTests/EncryptionRoundtripTests.swift` (новый)
- `IWishTests/ItemPriceModeTests.swift` (новый)

---

## 7. Implementation order (для plan-doc)

1. Migration foundation — preserve-unknown-keys в FirestoreService + Item/Wishlist Optional fields + backfill skeleton
2. AuthService name gate + NameRecoveryView
3. RemoteConfigService + ForceUpdateBlockingView + RootView gate
4. Description sync (#14) + другие missing fields (coverImageData, linkMetadataData, probationEndAt)
5. Memberships userName (#5/#12 enhanced)
6. UI правки (keyboard, decimal, tier emoji, version caption, card radius, safe area)
7. Range pricing (#8) — модель + UI
8. Gradient hue picker (#7) — модель + UI
9. iPad адаптация (#15) — project settings + RootView split + grid
10. Rate limiter cap (#1)
11. Tests
12. Build + manual test на iPhone Влада + iPad
13. Submit к ASC
