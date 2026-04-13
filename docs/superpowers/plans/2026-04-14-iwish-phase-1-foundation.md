# I Wish — Phase 1: Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Поднять project scaffolding, локальный data layer (SwiftData без CloudKit пока), сервисы (sort index, image compression, mesh covers) и минимальный UI для ручной проверки CRUD. По завершении — работающее offline-приложение, в котором можно создавать вишлисты и айтемы и видеть их в списках.

**Architecture:** Чистая SwiftData-based слойка. Модели `Wishlist`, `Item`, `AppSettings` живут в App Group SwiftData container (CloudKit не подключаем — это Phase 2). Сервисы (`SortIndexCalculator`, `ImageCompressor`, `DefaultCoverGenerator`) — stateless static utility-структуры с unit-тестами через Swift Testing. UI — несколько SwiftUI экранов: Home (список вишлистов), WishlistDetail (список айтемов), формы создания, бейсик Settings.

**Tech Stack:** SwiftUI · SwiftData (iOS 26+) · Swift Testing · UIKit (только для `UIImage` resize) · CoreImage (later phases)

**Scope explicitly OUT for Phase 1 (in later phases):**
- CloudKit sync, encryption (`@Attribute(.encrypt)`) — Phase 2
- Tier badges/UI с группировкой и сортировками — Phase 2/3 (модели и логика готовы, UI группировки добавляем позже)
- Liquid Glass полировка, темы — Phase 2 (UI пока в дефолтном стиле, тогглы темы — да, но без полного дизайна)
- Probation, Archive, Smart URLs — Phase 3
- Sharing (CKShare, QR), Share Extension — Phase 4
- Onboarding — Phase 5

**Phase 1 acceptance criteria:**
1. Открываешь приложение — пустой Home с кнопкой `+ Новый список`
2. Создаёшь вишлист (имя) — он появляется в списке
3. Тапаешь вишлист — открывается список айтемов (пустой)
4. Создаёшь айтем (имя, важность, цена) — он появляется
5. Удаляешь айтем свайпом
6. Удаляешь вишлист свайпом
7. Меняешь тему в Settings — UI перерисовывается
8. Все unit-тесты зелёные

---

## File Structure

После Phase 1 структура проекта:

```
IWish/
├── IWishApp.swift                    # App entry, ModelContainer wiring
├── ContentView.swift                 # Root container — переход на HomeView
├── Models/
│   ├── Wishlist.swift                # @Model
│   ├── Item.swift                    # @Model (заменяет starter Item.swift)
│   ├── ItemTier.swift                # enum + display helpers
│   ├── AppSettings.swift             # @Model (локально)
│   └── ThemeMode.swift               # enum (.light/.dark/.system)
├── Services/
│   ├── ModelContainerFactory.swift   # SwiftData container (без CloudKit пока)
│   ├── SortIndexCalculator.swift     # midpoint, rebalance helpers
│   ├── ImageCompressor.swift         # JPEG compression utility
│   └── DefaultCoverGenerator.swift   # MeshGradient seed from UUID
├── Views/
│   ├── HomeView.swift                # Список вишлистов
│   ├── WishlistDetailView.swift      # Список айтемов внутри вишлиста
│   ├── AddWishlistSheet.swift        # Форма создания вишлиста
│   ├── AddItemSheet.swift            # Форма создания айтема
│   ├── SettingsView.swift            # Настройки (только тема в Phase 1)
│   └── Components/
│       └── DefaultCoverView.swift    # Renders MeshGradient или фото
└── Assets.xcassets

IWishTests/                            # Новый target — добавить через Xcode
├── ItemTierTests.swift
├── SortIndexCalculatorTests.swift
├── ImageCompressorTests.swift
├── DefaultCoverGeneratorTests.swift
├── WishlistModelTests.swift
└── ItemModelTests.swift
```

**Принципы файловой декомпозиции:**
- Один `@Model` на файл — модели читаются изолированно, тесты прицелены.
- Сервисы — `enum`/`struct` без состояния, легко тестируются.
- Views в `Views/`, переиспользуемые куски — в `Views/Components/`.
- Тесты — параллельные target, общий namespace `IWish` через `@testable import IWish`.

---

## Task 1: Подготовить Xcode project — capabilities + folder structure

**Files:**
- Modify: `IWish.xcodeproj/project.pbxproj` (через Xcode UI)
- Create: пустые группы `IWish/Models/`, `IWish/Services/`, `IWish/Views/`, `IWish/Views/Components/`

- [ ] **Step 1: Открыть проект в Xcode**

```bash
open IWish.xcodeproj
```

- [ ] **Step 2: Добавить test target IWishTests**

В Xcode → File → New → Target → iOS → Unit Testing Bundle → Product Name: `IWishTests` → Project: IWish → Target to be Tested: IWish → Finish.

- [ ] **Step 3: Создать группы папок в Xcode Project Navigator**

Right-click на группе IWish → New Group: `Models`, `Services`, `Views`, далее внутри `Views` → New Group: `Components`.

- [ ] **Step 4: Включить iCloud capability (заготовка для Phase 2)**

Project → IWish target → Signing & Capabilities → `+ Capability` → iCloud → отметить **CloudKit** → containers: оставить пустым, добавим в Phase 2.

(Сейчас не используется, но добавляем pre-emptively чтобы entitlements file существовал.)

- [ ] **Step 5: Включить Background Modes (заготовка для Phase 4)**

`+ Capability` → Background Modes → отметить `Background fetch`. Оставляем для будущего `BGAppRefreshTask`.

- [ ] **Step 6: Сохранить и закоммитить структурные изменения**

```bash
git add IWish.xcodeproj IWish/IWish.entitlements 2>/dev/null || git add IWish.xcodeproj
git commit -m "chore: scaffold Xcode targets and capabilities for Phase 1"
```

---

## Task 2: ItemTier enum

**Files:**
- Create: `IWish/Models/ItemTier.swift`
- Test: `IWishTests/ItemTierTests.swift`

- [ ] **Step 1: Написать failing test**

Создать `IWishTests/ItemTierTests.swift`:

```swift
import Testing
@testable import IWish

@Suite("ItemTier")
struct ItemTierTests {
    @Test("default tier is .maybe")
    func defaultIsMaybe() {
        #expect(ItemTier.defaultTier == .maybe)
    }

    @Test("each tier has unique icon")
    func uniqueIcons() {
        let icons = Set(ItemTier.allCases.map(\.icon))
        #expect(icons.count == ItemTier.allCases.count)
    }

    @Test("each tier has non-empty russian label")
    func labelsPresent() {
        for tier in ItemTier.allCases {
            #expect(!tier.label.isEmpty)
        }
    }

    @Test("rawValue round-trip")
    func rawValueRoundTrip() {
        for tier in ItemTier.allCases {
            #expect(ItemTier(rawValue: tier.rawValue) == tier)
        }
    }
}
```

- [ ] **Step 2: Запустить тест — должен fail (тип не существует)**

```bash
xcodebuild test -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:IWishTests/ItemTierTests
```

Expected: BUILD FAILED — `Cannot find 'ItemTier' in scope`.

- [ ] **Step 3: Создать `IWish/Models/ItemTier.swift`**

```swift
import Foundation

enum ItemTier: String, Codable, CaseIterable, Sendable, Identifiable {
    case must
    case maybe
    case idea

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .must:  return "🔥"
        case .maybe: return "🤔"
        case .idea:  return "💭"
        }
    }

    var label: String {
        switch self {
        case .must:  return "Обязательно"
        case .maybe: return "Пока думаю"
        case .idea:  return "Просто идея"
        }
    }

    static var defaultTier: ItemTier { .maybe }
}
```

- [ ] **Step 4: Запустить тест — должен PASS**

```bash
xcodebuild test -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:IWishTests/ItemTierTests
```

Expected: `Test Suite 'ItemTier' passed`.

- [ ] **Step 5: Commit**

```bash
git add IWish/Models/ItemTier.swift IWishTests/ItemTierTests.swift
git commit -m "feat: add ItemTier enum with display helpers"
```

---

## Task 3: ThemeMode enum

**Files:**
- Create: `IWish/Models/ThemeMode.swift`

(Без отдельного теста — простой enum с маппингом на `ColorScheme?`. Тестируется визуально через UI в Task 13.)

- [ ] **Step 1: Создать `IWish/Models/ThemeMode.swift`**

```swift
import SwiftUI

enum ThemeMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Системная"
        case .light:  return "Светлая"
        case .dark:   return "Тёмная"
        }
    }

    /// `nil` означает «использовать системную тему».
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add IWish/Models/ThemeMode.swift
git commit -m "feat: add ThemeMode enum mapping to SwiftUI ColorScheme"
```

---

## Task 4: Wishlist model

**Files:**
- Create: `IWish/Models/Wishlist.swift`
- Test: `IWishTests/WishlistModelTests.swift`

- [ ] **Step 1: Написать failing test**

Создать `IWishTests/WishlistModelTests.swift`:

```swift
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
        #expect(wishlist.items.isEmpty)
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
```

- [ ] **Step 2: Запустить тест — должен fail (типа `Wishlist` нет)**

```bash
xcodebuild test -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:IWishTests/WishlistModelTests
```

Expected: BUILD FAILED — `Cannot find 'Wishlist' in scope`.

- [ ] **Step 3: Создать `IWish/Models/Wishlist.swift`**

```swift
import Foundation
import SwiftData

@Model
final class Wishlist {
    // Без `@Attribute(.unique)` — CloudKit mirror не поддерживает unique constraints.
    // Уникальность гарантируется `UUID()`.
    var id: UUID
    var name: String
    var coverImageData: Data?
    var coverEmoji: String?
    var createdAt: Date
    var updatedAt: Date
    var ownerRecordID: String?

    @Relationship(deleteRule: .cascade, inverse: \Item.wishlist)
    var items: [Item] = []

    init(
        name: String,
        coverImageData: Data? = nil,
        coverEmoji: String? = nil,
        ownerRecordID: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.coverImageData = coverImageData
        self.coverEmoji = coverEmoji
        self.createdAt = .now
        self.updatedAt = .now
        self.ownerRecordID = ownerRecordID
    }
}
```

(Тест ссылается на `Item` и `AppSettings` — пока их нет. Тест не скомпилируется до Tasks 5-6. Это OK — следующие задачи добавят их.)

- [ ] **Step 4: Не запускать тест ещё (зависит от следующих моделей). Перейти к Task 5.**

---

## Task 5: Item model

**Files:**
- Modify: `IWish/Item.swift` (заменить starter template целиком)
- Move: `IWish/Item.swift` → `IWish/Models/Item.swift`
- Test: `IWishTests/ItemModelTests.swift`

- [ ] **Step 1: Написать failing test**

Создать `IWishTests/ItemModelTests.swift`:

```swift
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
        #expect(fetched.first?.items.count == 1)
        #expect(fetched.first?.items.first?.name == "Belongs")
    }
}
```

- [ ] **Step 2: Удалить старый `IWish/Item.swift`**

```bash
rm IWish/Item.swift
```

(Через Xcode — выбрать Item.swift в Project Navigator → Delete → Move to Trash. Пересинхронизировать pbxproj если нужно.)

- [ ] **Step 3: Создать `IWish/Models/Item.swift`**

```swift
import Foundation
import SwiftData

@Model
final class Item {
    // Без `@Attribute(.unique)` — см. коммент в `Wishlist`.
    var id: UUID
    var name: String
    var descriptionText: String?
    var coverImageData: Data?
    var coverEmoji: String?
    var price: Decimal?
    var currency: String
    var url: String?
    var linkMetadataData: Data?
    var tier: ItemTier
    var sortIndex: Double
    var probationEndAt: Date?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var wishlist: Wishlist?

    init(
        name: String,
        tier: ItemTier = .maybe,
        sortIndex: Double = 1000.0,
        currency: String = "RUB",
        price: Decimal? = nil,
        descriptionText: String? = nil,
        url: String? = nil,
        coverImageData: Data? = nil,
        coverEmoji: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.descriptionText = descriptionText
        self.coverImageData = coverImageData
        self.coverEmoji = coverEmoji
        self.price = price
        self.currency = currency
        self.url = url
        self.linkMetadataData = nil
        self.tier = tier
        self.sortIndex = sortIndex
        self.probationEndAt = nil
        self.isArchived = false
        self.createdAt = .now
        self.updatedAt = .now
    }
}
```

- [ ] **Step 4: Добавить созданный файл в Xcode target**

В Xcode Project Navigator: drag `Models/Item.swift` → IWish target. Если файл уже добавлен через файловую систему — File → Add Files to "IWish" → выбрать `Models/Item.swift` → Add to: IWish.

- [ ] **Step 5: Не запускать тест — нужно AppSettings (Task 6)**

---

## Task 6: AppSettings model

**Files:**
- Create: `IWish/Models/AppSettings.swift`

- [ ] **Step 1: Создать `IWish/Models/AppSettings.swift`**

Минимальная Phase 1 версия — только тема и валюта. Остальные поля добавим в Phase 5 (Settings polish).

```swift
import Foundation
import SwiftData

@Model
final class AppSettings {
    /// Singleton — всегда один instance в БД. Инвариант поддерживается
    /// `loadOrCreate(in:)`, а не schema constraint (CloudKit mirror
    /// не поддерживает `@Attribute(.unique)`).
    var id: UUID
    var themeModeRaw: String
    var defaultCurrency: String
    var hasCompletedOnboarding: Bool

    var themeMode: ThemeMode {
        get { ThemeMode(rawValue: themeModeRaw) ?? .system }
        set { themeModeRaw = newValue.rawValue }
    }

    init(
        themeMode: ThemeMode = .system,
        defaultCurrency: String = "RUB",
        hasCompletedOnboarding: Bool = false
    ) {
        self.id = UUID()
        self.themeModeRaw = themeMode.rawValue
        self.defaultCurrency = defaultCurrency
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    /// Загружает существующие или создаёт новые settings. Гарантирует ровно один instance.
    static func loadOrCreate(in context: ModelContext) -> AppSettings {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let fresh = AppSettings()
        context.insert(fresh)
        try? context.save()
        return fresh
    }
}
```

- [ ] **Step 2: Запустить все тесты моделей — должны PASS**

```bash
xcodebuild test -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:IWishTests/WishlistModelTests -only-testing:IWishTests/ItemModelTests
```

Expected: оба suite — `passed`.

- [ ] **Step 3: Commit**

```bash
git add IWish/Models/Wishlist.swift IWish/Models/Item.swift IWish/Models/AppSettings.swift IWishTests/WishlistModelTests.swift IWishTests/ItemModelTests.swift IWish.xcodeproj
git rm IWish/Item.swift 2>/dev/null || true
git commit -m "feat: add Wishlist, Item, AppSettings SwiftData models"
```

---

## Task 7: SortIndexCalculator

**Files:**
- Create: `IWish/Services/SortIndexCalculator.swift`
- Test: `IWishTests/SortIndexCalculatorTests.swift`

- [ ] **Step 1: Написать failing test**

Создать `IWishTests/SortIndexCalculatorTests.swift`:

```swift
import Testing
@testable import IWish

@Suite("SortIndexCalculator")
struct SortIndexCalculatorTests {
    @Test("midpoint between two values")
    func midpointBetween() {
        #expect(SortIndexCalculator.midpoint(after: 1000, before: 2000) == 1500)
    }

    @Test("midpoint when no upper neighbor — append step")
    func midpointAppend() {
        #expect(SortIndexCalculator.midpoint(after: 5000, before: nil) == 6000)
    }

    @Test("midpoint when no lower neighbor — prepend step")
    func midpointPrepend() {
        #expect(SortIndexCalculator.midpoint(after: nil, before: 1000) == 0)
    }

    @Test("midpoint when list is empty — initial step")
    func midpointEmpty() {
        #expect(SortIndexCalculator.midpoint(after: nil, before: nil) == 1000)
    }

    @Test("needsRebalance is false for spaced values")
    func noRebalanceForSpaced() {
        #expect(!SortIndexCalculator.needsRebalance([1000, 2000, 3000]))
    }

    @Test("needsRebalance is true for collapsing values")
    func rebalanceForCollapsed() {
        #expect(SortIndexCalculator.needsRebalance([1000, 1000.0001, 2000]))
    }

    @Test("rebalanced returns step-spaced sequence")
    func rebalancedSequence() {
        #expect(SortIndexCalculator.rebalanced(count: 3) == [1000, 2000, 3000])
    }

    @Test("rebalanced of zero returns empty")
    func rebalancedZero() {
        #expect(SortIndexCalculator.rebalanced(count: 0) == [])
    }
}
```

- [ ] **Step 2: Запустить тест — должен fail**

```bash
xcodebuild test -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:IWishTests/SortIndexCalculatorTests
```

Expected: BUILD FAILED — `Cannot find 'SortIndexCalculator' in scope`.

- [ ] **Step 3: Создать `IWish/Services/SortIndexCalculator.swift`**

```swift
import Foundation

enum SortIndexCalculator {
    static let initialStep: Double = 1000.0
    static let minGap: Double = 0.001

    /// Возвращает midpoint между двумя соседями. nil = край списка.
    static func midpoint(after lower: Double?, before upper: Double?) -> Double {
        switch (lower, upper) {
        case (nil, nil):
            return initialStep
        case let (l?, nil):
            return l + initialStep
        case let (nil, u?):
            return u - initialStep
        case let (l?, u?):
            return (l + u) / 2.0
        }
    }

    /// true если хотя бы одна пара соседних значений сблизилась меньше чем на minGap.
    static func needsRebalance(_ sortedIndexes: [Double]) -> Bool {
        guard sortedIndexes.count >= 2 else { return false }
        for i in 1..<sortedIndexes.count {
            if sortedIndexes[i] - sortedIndexes[i - 1] < minGap {
                return true
            }
        }
        return false
    }

    /// Возвращает последовательность 1000, 2000, ... step * count.
    static func rebalanced(count: Int) -> [Double] {
        guard count > 0 else { return [] }
        return (1...count).map { Double($0) * initialStep }
    }
}
```

- [ ] **Step 4: Запустить тест — должен PASS**

```bash
xcodebuild test -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:IWishTests/SortIndexCalculatorTests
```

Expected: 8 tests passed.

- [ ] **Step 5: Commit**

```bash
git add IWish/Services/SortIndexCalculator.swift IWishTests/SortIndexCalculatorTests.swift
git commit -m "feat: add SortIndexCalculator with midpoint + rebalance helpers"
```

---

## Task 8: ImageCompressor

**Files:**
- Create: `IWish/Services/ImageCompressor.swift`
- Test: `IWishTests/ImageCompressorTests.swift`

- [ ] **Step 1: Написать failing test**

Создать `IWishTests/ImageCompressorTests.swift`:

```swift
import Testing
import UIKit
@testable import IWish

@Suite("ImageCompressor")
struct ImageCompressorTests {
    @Test("compress returns data ≤ targetMaxBytes for typical input")
    func compressSmall() throws {
        let image = makeImage(size: CGSize(width: 800, height: 600), color: .red)
        let data = try #require(ImageCompressor.compress(image))
        #expect(data.count <= ImageCompressor.targetMaxBytes)
    }

    @Test("compress downscales oversized image")
    func compressLarge() throws {
        let image = makeImage(size: CGSize(width: 4000, height: 3000), color: .blue)
        let data = try #require(ImageCompressor.compress(image))
        let restored = try #require(UIImage(data: data))
        let maxEdge = max(restored.size.width, restored.size.height)
        #expect(maxEdge <= ImageCompressor.maxEdge + 1)  // ±1 для rounding
    }

    @Test("compress preserves small image dimensions")
    func compressSmallPreserves() throws {
        let original = makeImage(size: CGSize(width: 200, height: 200), color: .green)
        let data = try #require(ImageCompressor.compress(original))
        let restored = try #require(UIImage(data: data))
        #expect(abs(restored.size.width - 200) < 2)
    }

    private func makeImage(size: CGSize, color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
```

- [ ] **Step 2: Запустить — fail**

```bash
xcodebuild test -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:IWishTests/ImageCompressorTests
```

Expected: BUILD FAILED — `Cannot find 'ImageCompressor'`.

- [ ] **Step 3: Создать `IWish/Services/ImageCompressor.swift`**

```swift
import UIKit

enum ImageCompressor {
    static let maxEdge: CGFloat = 1024
    static let primaryQuality: CGFloat = 0.7
    static let fallbackQuality: CGFloat = 0.5
    static let targetMaxBytes: Int = 500_000  // 500 KB

    /// Сжимает изображение в JPEG, стремится уложиться в targetMaxBytes.
    /// Сначала ресайз до maxEdge, потом quality 0.7. Если всё ещё больше — quality 0.5.
    static func compress(_ image: UIImage) -> Data? {
        let resized = image.resized(maxEdge: maxEdge)
        if let primary = resized.jpegData(compressionQuality: primaryQuality),
           primary.count <= targetMaxBytes {
            return primary
        }
        return resized.jpegData(compressionQuality: fallbackQuality)
    }
}

private extension UIImage {
    func resized(maxEdge: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxEdge else { return self }
        let scale = maxEdge / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in self.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
```

- [ ] **Step 4: Запустить — должен PASS**

```bash
xcodebuild test -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:IWishTests/ImageCompressorTests
```

Expected: 3 tests passed.

- [ ] **Step 5: Commit**

```bash
git add IWish/Services/ImageCompressor.swift IWishTests/ImageCompressorTests.swift
git commit -m "feat: add ImageCompressor for cover image JPEG compression"
```

---

## Task 9: DefaultCoverGenerator

**Files:**
- Create: `IWish/Services/DefaultCoverGenerator.swift`
- Create: `IWish/Views/Components/DefaultCoverView.swift`
- Test: `IWishTests/DefaultCoverGeneratorTests.swift`

- [ ] **Step 1: Написать failing test**

Создать `IWishTests/DefaultCoverGeneratorTests.swift`:

```swift
import Testing
import Foundation
@testable import IWish

@Suite("DefaultCoverGenerator")
struct DefaultCoverGeneratorTests {
    @Test("same UUID always returns same palette")
    func deterministic() {
        let id = UUID()
        let first = DefaultCoverGenerator.paletteIndex(for: id)
        let second = DefaultCoverGenerator.paletteIndex(for: id)
        #expect(first == second)
    }

    @Test("different UUIDs distribute across palettes")
    func distribution() {
        var seen = Set<Int>()
        for _ in 0..<200 {
            seen.insert(DefaultCoverGenerator.paletteIndex(for: UUID()))
        }
        // С 200 UUID и 8 палитрами вероятность увидеть <4 разных — околонулевая.
        #expect(seen.count >= 4)
    }

    @Test("palette index in valid range")
    func validRange() {
        for _ in 0..<50 {
            let idx = DefaultCoverGenerator.paletteIndex(for: UUID())
            #expect(idx >= 0)
            #expect(idx < DefaultCoverGenerator.paletteCount)
        }
    }
}
```

- [ ] **Step 2: Запустить — fail**

```bash
xcodebuild test -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:IWishTests/DefaultCoverGeneratorTests
```

Expected: BUILD FAILED — `Cannot find 'DefaultCoverGenerator'`.

- [ ] **Step 3: Создать `IWish/Services/DefaultCoverGenerator.swift`**

```swift
import SwiftUI

enum DefaultCoverGenerator {
    /// Палитры из 3 цветов каждая. Подобраны для соответствия Apple system colors.
    static let palettes: [[Color]] = [
        [.blue, .indigo, .purple],
        [.orange, .pink, .red],
        [.green, .mint, .teal],
        [.purple, .pink, .red],
        [.cyan, .blue, .indigo],
        [.yellow, .orange, .red],
        [.mint, .teal, .cyan],
        [.indigo, .purple, .pink],
    ]

    static var paletteCount: Int { palettes.count }

    /// Детерминированный индекс палитры по UUID. Стабильный между запусками.
    static func paletteIndex(for id: UUID) -> Int {
        let bytes = withUnsafeBytes(of: id.uuid) { Data($0) }
        let sum = bytes.reduce(into: 0) { $0 = ($0 &+ Int($1)) }
        return abs(sum) % palettes.count
    }

    /// Возвращает 3 цвета для данного UUID.
    static func colors(for id: UUID) -> [Color] {
        palettes[paletteIndex(for: id)]
    }
}
```

- [ ] **Step 4: Запустить тест — PASS**

```bash
xcodebuild test -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:IWishTests/DefaultCoverGeneratorTests
```

Expected: 3 tests passed.

- [ ] **Step 5: Создать `IWish/Views/Components/DefaultCoverView.swift`**

```swift
import SwiftUI

/// Рендерит mesh-градиент по UUID для дефолтной обложки айтема/вишлиста.
/// Если есть `imageData` — рендерит фото вместо градиента.
struct DefaultCoverView: View {
    let id: UUID
    var imageData: Data? = nil
    var emoji: String? = nil

    var body: some View {
        ZStack {
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                meshBackground
                if let emoji {
                    Text(emoji)
                        .font(.system(size: 40))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var meshBackground: some View {
        let colors = DefaultCoverGenerator.colors(for: id)
        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                .init(0, 0),   .init(0.5, 0),   .init(1, 0),
                .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                .init(0, 1),   .init(0.5, 1),   .init(1, 1),
            ],
            colors: [
                colors[0], colors[1], colors[2],
                colors[1], colors[2], colors[0],
                colors[2], colors[0], colors[1],
            ]
        )
    }
}

#Preview {
    HStack {
        DefaultCoverView(id: UUID())
            .frame(width: 80, height: 80)
        DefaultCoverView(id: UUID(), emoji: "🎧")
            .frame(width: 80, height: 80)
    }
    .padding()
}
```

- [ ] **Step 6: Commit**

```bash
git add IWish/Services/DefaultCoverGenerator.swift IWish/Views/Components/DefaultCoverView.swift IWishTests/DefaultCoverGeneratorTests.swift
git commit -m "feat: add DefaultCoverGenerator + DefaultCoverView with MeshGradient"
```

---

## Task 10: ModelContainerFactory

**Files:**
- Create: `IWish/Services/ModelContainerFactory.swift`
- Modify: `IWish/IWishApp.swift`

(Без unit-теста — это thin wrapper. Smoke-проверка в UI.)

- [ ] **Step 1: Создать `IWish/Services/ModelContainerFactory.swift`**

```swift
import Foundation
import SwiftData

enum ModelContainerFactory {
    /// Production-контейнер. Phase 1 — без CloudKit, локально.
    /// В Phase 2 здесь добавится `cloudKitDatabase: .private(...)` и `@Attribute(.encrypt)`.
    static func makeProductionContainer() -> ModelContainer {
        let schema = Schema([
            Wishlist.self,
            Item.self,
            AppSettings.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
```

- [ ] **Step 2: Заменить `IWish/IWishApp.swift`**

```swift
import SwiftUI
import SwiftData

@main
struct IWishApp: App {
    let container: ModelContainer

    init() {
        self.container = ModelContainerFactory.makeProductionContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
```

(`RootView` будет создан в Task 11. Build пока что fail — это ожидаемо.)

- [ ] **Step 3: Commit**

```bash
git add IWish/Services/ModelContainerFactory.swift IWish/IWishApp.swift
git commit -m "feat: wire ModelContainerFactory into app entry"
```

---

## Task 11: RootView + минимальный HomeView

**Files:**
- Create: `IWish/Views/HomeView.swift`
- Modify: `IWish/ContentView.swift` → переименовать в `RootView.swift` или удалить и создать `RootView.swift`

- [ ] **Step 1: Удалить старый `IWish/ContentView.swift`**

В Xcode: правый клик на ContentView.swift → Delete → Move to Trash.

- [ ] **Step 2: Создать `IWish/Views/RootView.swift`**

```swift
import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]

    var body: some View {
        NavigationStack {
            HomeView()
        }
        .preferredColorScheme(activeSettings.themeMode.colorScheme)
        .onAppear {
            // Гарантируем что AppSettings существует в БД.
            if settingsList.isEmpty {
                _ = AppSettings.loadOrCreate(in: context)
            }
        }
    }

    private var activeSettings: AppSettings {
        settingsList.first ?? AppSettings()
    }
}
```

- [ ] **Step 3: Создать `IWish/Views/HomeView.swift`**

```swift
import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Wishlist.createdAt, order: .reverse) private var wishlists: [Wishlist]
    @State private var showingAddSheet = false
    @State private var showingSettings = false

    var body: some View {
        Group {
            if wishlists.isEmpty {
                emptyState
            } else {
                wishlistList
            }
        }
        .navigationTitle("Желания")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddWishlistSheet()
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { SettingsView() }
        }
        .overlay(alignment: .bottom) {
            addButton
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Пока пусто")
                .font(.title3)
            Text("Создай первый список — начнём собирать желания.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var wishlistList: some View {
        List {
            ForEach(wishlists) { wishlist in
                NavigationLink {
                    WishlistDetailView(wishlist: wishlist)
                } label: {
                    HStack(spacing: 12) {
                        DefaultCoverView(
                            id: wishlist.id,
                            imageData: wishlist.coverImageData,
                            emoji: wishlist.coverEmoji
                        )
                        .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(wishlist.name)
                                .font(.headline)
                            Text("\(wishlist.items.count) желаний")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete(perform: deleteWishlists)
        }
    }

    private var addButton: some View {
        Button {
            showingAddSheet = true
        } label: {
            Label("Новый список", systemImage: "plus")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.bottom, 16)
    }

    private func deleteWishlists(offsets: IndexSet) {
        for index in offsets {
            context.delete(wishlists[index])
        }
        try? context.save()
    }
}
```

(Build всё ещё fail — `WishlistDetailView`, `AddWishlistSheet`, `SettingsView` не существуют. Tasks 12-14 их добавят.)

- [ ] **Step 4: Commit**

```bash
git add IWish/Views/RootView.swift IWish/Views/HomeView.swift
git rm IWish/ContentView.swift 2>/dev/null || true
git commit -m "feat: add RootView + HomeView with empty state and wishlist list"
```

---

## Task 12: AddWishlistSheet

**Files:**
- Create: `IWish/Views/AddWishlistSheet.swift`

- [ ] **Step 1: Создать `IWish/Views/AddWishlistSheet.swift`**

```swift
import SwiftUI
import SwiftData

struct AddWishlistSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Например: На день рождения", text: $name)
                        .textInputAutocapitalization(.sentences)
                }
            }
            .navigationTitle("Новый список")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let wishlist = Wishlist(name: name.trimmingCharacters(in: .whitespaces))
        context.insert(wishlist)
        try? context.save()
        dismiss()
    }
}

#Preview {
    AddWishlistSheet()
        .modelContainer(for: [Wishlist.self, Item.self, AppSettings.self], inMemory: true)
}
```

- [ ] **Step 2: Commit**

```bash
git add IWish/Views/AddWishlistSheet.swift
git commit -m "feat: add AddWishlistSheet for creating wishlists"
```

---

## Task 13: WishlistDetailView + AddItemSheet

**Files:**
- Create: `IWish/Views/WishlistDetailView.swift`
- Create: `IWish/Views/AddItemSheet.swift`

- [ ] **Step 1: Создать `IWish/Views/WishlistDetailView.swift`**

```swift
import SwiftUI
import SwiftData

struct WishlistDetailView: View {
    @Environment(\.modelContext) private var context
    let wishlist: Wishlist
    @State private var showingAddItem = false

    private var sortedItems: [Item] {
        wishlist.items
            .filter { !$0.isArchived }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    var body: some View {
        Group {
            if sortedItems.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .navigationTitle(wishlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddItem) {
            AddItemSheet(wishlist: wishlist)
        }
        .overlay(alignment: .bottom) {
            addButton
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Список пуст")
                .font(.title3)
            Text("Добавь первое желание.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var itemList: some View {
        List {
            ForEach(sortedItems) { item in
                HStack(spacing: 12) {
                    DefaultCoverView(
                        id: item.id,
                        imageData: item.coverImageData,
                        emoji: item.coverEmoji
                    )
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(item.tier.icon)
                            Text(item.name)
                                .font(.subheadline)
                        }
                        if let description = item.descriptionText, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if let price = item.price {
                        Text(formatPrice(price, currency: item.currency))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: deleteItems)
        }
    }

    private var addButton: some View {
        Button {
            showingAddItem = true
        } label: {
            Label("Новое желание", systemImage: "plus")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.bottom, 16)
    }

    private func deleteItems(offsets: IndexSet) {
        for index in offsets {
            context.delete(sortedItems[index])
        }
        try? context.save()
    }

    private func formatPrice(_ price: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: price as NSDecimalNumber) ?? "\(price) \(currency)"
    }
}
```

- [ ] **Step 2: Создать `IWish/Views/AddItemSheet.swift`**

```swift
import SwiftUI
import SwiftData

struct AddItemSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    let wishlist: Wishlist

    @State private var name: String = ""
    @State private var descriptionText: String = ""
    @State private var tier: ItemTier = .maybe
    @State private var priceString: String = ""

    private var defaultCurrency: String {
        settingsList.first?.defaultCurrency ?? "RUB"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Чего хочется?", text: $name)
                        .textInputAutocapitalization(.sentences)
                }
                Section("Важность") {
                    Picker("Важность", selection: $tier) {
                        ForEach(ItemTier.allCases) { tier in
                            Text("\(tier.icon) \(tier.label)").tag(tier)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Цена") {
                    TextField("0", text: $priceString)
                        .keyboardType(.numberPad)
                }
                Section("Описание") {
                    TextField("Опционально", text: $descriptionText, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Новое желание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let nextSortIndex = nextSortIndexForTier(tier)
        let item = Item(
            name: trimmedName,
            tier: tier,
            sortIndex: nextSortIndex,
            currency: defaultCurrency,
            price: parsePrice(priceString),
            descriptionText: descriptionText.isEmpty ? nil : descriptionText
        )
        item.wishlist = wishlist
        context.insert(item)
        try? context.save()
        dismiss()
    }

    /// Новый айтем — в конец своего tier (max(sortIndex) + step).
    private func nextSortIndexForTier(_ tier: ItemTier) -> Double {
        let tierItems = wishlist.items.filter { $0.tier == tier && !$0.isArchived }
        let maxIndex = tierItems.map(\.sortIndex).max()
        return SortIndexCalculator.midpoint(after: maxIndex, before: nil)
    }

    private func parsePrice(_ string: String) -> Decimal? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add IWish/Views/WishlistDetailView.swift IWish/Views/AddItemSheet.swift
git commit -m "feat: add WishlistDetailView and AddItemSheet"
```

---

## Task 14: SettingsView (минимальная)

**Files:**
- Create: `IWish/Views/SettingsView.swift`

- [ ] **Step 1: Создать `IWish/Views/SettingsView.swift`**

```swift
import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    private var settings: AppSettings {
        settingsList.first ?? AppSettings.loadOrCreate(in: context)
    }

    var body: some View {
        Form {
            Section("Внешний вид") {
                Picker("Тема", selection: themeBinding) {
                    ForEach(ThemeMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }
            Section("Желания") {
                Picker("Валюта по умолчанию", selection: currencyBinding) {
                    Text("Рубль (RUB)").tag("RUB")
                    Text("Доллар (USD)").tag("USD")
                }
            }
        }
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { dismiss() }
            }
        }
    }

    private var themeBinding: Binding<ThemeMode> {
        Binding(
            get: { settings.themeMode },
            set: {
                settings.themeMode = $0
                try? context.save()
            }
        )
    }

    private var currencyBinding: Binding<String> {
        Binding(
            get: { settings.defaultCurrency },
            set: {
                settings.defaultCurrency = $0
                try? context.save()
            }
        )
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .modelContainer(for: [Wishlist.self, Item.self, AppSettings.self], inMemory: true)
    }
}
```

- [ ] **Step 2: Build всего проекта — должен компилироваться**

```bash
xcodebuild build -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Запустить ВСЕ тесты — все должны PASS**

```bash
xcodebuild test -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: все suite passed.

- [ ] **Step 4: Commit**

```bash
git add IWish/Views/SettingsView.swift
git commit -m "feat: add SettingsView with theme and currency pickers"
```

---

## Task 15: Manual smoke test + acceptance verification

**Files:** —

- [ ] **Step 1: Запустить приложение в симуляторе**

В Xcode → Product → Run (⌘R), target: iPhone 17 Pro simulator.

- [ ] **Step 2: Пройти acceptance criteria вручную**

Проверить пункты из header:
1. ✅ Открываешь — пустой Home + кнопка
2. ✅ Создаёшь вишлист → появляется в списке
3. ✅ Тапаешь вишлист → открывается пустой список айтемов
4. ✅ Создаёшь айтем → появляется
5. ✅ Удаляешь айтем свайпом
6. ✅ Удаляешь вишлист свайпом (back из detail → swipe)
7. ✅ Меняешь тему в Settings → перерисовка
8. ✅ Все юнит-тесты зелёные

- [ ] **Step 3: Если что-то не работает — фикс + коммит. Если всё ок — финальный коммит-маркер**

```bash
git commit --allow-empty -m "chore: phase 1 manual smoke test passed"
```

---

## Phase 1 → Phase 2 transition

После завершения Phase 1 у тебя:
- Working offline iOS app
- SwiftData layer с тестами
- Минимальный UI для CRUD
- Чистая структура папок

**Phase 2** добавит:
- CloudKit container + private DB sync
- `@Attribute(.encrypt)` на user-facing полях
- iCloud account status gate
- Liquid Glass дизайн на ключевых экранах
- Tier-секции с группировкой и итогами цен
- Сортировки (по дате, цене, имени) + фильтр «скрыть idea»
- Drag-reorder с пересчётом sortIndex

Фаза 2 пишется отдельным планом после завершения Phase 1.

---

## Self-Review Notes

**Spec coverage (Phase 1 scope only):**
- ✅ Project scaffolding (M0): capabilities + folder structure → Tasks 1, 10
- ✅ Local CRUD (M1, без sync): models + repos + tests → Tasks 2-9
- ✅ Базовый UI (slice of M3): home/wishlist detail/sheets/settings → Tasks 11-14

**Out of Phase 1 scope (отложено в следующие фазы — отмечено явно в header):**
- CloudKit sync, encryption — Phase 2
- Tier UI с группировкой, drag-reorder, сортировки/фильтры — Phase 2/3
- Probation, Archive, Smart URLs — Phase 3
- Sharing, Share Extension — Phase 4
- Onboarding — Phase 5

**Type consistency check:**
- `ItemTier.allCases` — используется в Tasks 2, 13, 14 — все ок
- `Wishlist.items` — relationship `[Item]`, используется в HomeView (count) и WishlistDetailView (filter+sort) — типы матчат
- `AppSettings.themeMode` — computed property из `themeModeRaw`, используется в RootView и SettingsView — типы матчат
- `SortIndexCalculator.midpoint(after:before:)` — используется в AddItemSheet — сигнатура матчит

**Placeholder scan:** нет TBD, TODO, "implement later" — все code blocks полные.
