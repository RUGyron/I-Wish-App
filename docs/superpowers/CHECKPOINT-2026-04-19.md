# Checkpoint: CloudKit Sharing — 2026-04-19

## Что сделано

### CloudKit Sharing (Tasks 1-8 из 10)
1. ✅ Entitlements: Associated Domains (`applinks:rugyron.github.io`) + ModelContainerFactory `.automatic`
2. ✅ CloudKitSharingService — PublicDB CRUD (ShareLink records) + CKShare accept + TTL cleanup
3. ✅ ShareManager rewrite — async, реальный CKShare + PublicDB ShareLink
4. ✅ InvitePreviewSheet — UI для incoming invites (gradient, emoji, details card)
5. ✅ JoinWishlistSheet — resolve shortID → InvitePreviewSheet → accept flow
6. ✅ Universal Links в IWishApp — обработка https://rugyron.github.io/I-Wish-App/j/{shortID}
7. ✅ HomeView shared badge — иконка person.2.fill рядом с именем shared wishlist
8. ✅ TTL rotation — deleteExpiredShareLinks() при запуске в RootView

### Real CKShare (только что добавлено)
- CloudKitSharingService.createCKShare() — query CD_Wishlist в private DB, создаёт CKShare с root record
- publicPermission: .readWrite для editor, .readOnly для viewer
- ShareManager хранит реальный CKShare.url в PublicDB (не фейковый URL)
- deleteCKShare() для revoke

### Toast система
- ToastOverlay.swift — глобальный toast manager
- Подключён к RootView через .toastOverlay()
- JoinWishlistSheet и ShareWishlistSheet используют toast вместо inline ошибок

### CloudKit Dashboard (ручная настройка)
- Record type `ShareLink` создан в Development environment
- Indexes: shortID (Queryable), expiresAt (Queryable)
- Security Roles: _icloud → ShareLink: Create ✅ Read ✅ Write ✅

## Что НЕ сделано

### Task 9: GitHub Pages AASA + Landing
- apple-app-site-association файл для Universal Links
- Fallback landing page для тех у кого нет приложения
- Нужен доступ к GitHub repo rugyron.github.io

### Task 10: Integration test on device
- Девайс был unavailable перед ребутом
- Нужно: build → install → test owner flow (QR генерация) → test receiver flow (scan → invite → accept)
- Ключевой тест: после accept — wishlist появляется у receiver

### Не протестировано
- Реальный CKShare creation (код написан, не запускался на девайсе)
- Accept flow end-to-end
- Два девайса одновременно

## Как продолжить

1. `xcodebuild -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS,id=17A9B107-CE43-5472-9087-F1C57E8F1E58' -configuration Debug`
2. Install + launch на девайсе
3. Тест: создать шеру → скопировать ссылку → на 2м девайсе вставить → InvitePreviewSheet → Accept
4. Если CKShare creation падает — смотреть ошибку, вероятно CD_id query или zone name

## Файлы изменённые в этой сессии

### Новые
- IWish/Services/CloudKitSharingService.swift
- IWish/Views/InvitePreviewSheet.swift
- IWish/Views/Components/ToastOverlay.swift
- docs/superpowers/specs/2026-04-18-cloudkit-sharing-design.md
- docs/superpowers/plans/2026-04-18-cloudkit-sharing.md

### Изменённые
- IWish/Services/ModelContainerFactory.swift (`.private` → `.automatic`)
- IWish/Services/ShareManager.swift (полный rewrite с real CKShare)
- IWish/Services/AppServices.swift (+ sharing)
- IWish/Views/ShareWishlistSheet.swift (async calls + toast)
- IWish/Views/JoinWishlistSheet.swift (resolve + InvitePreviewSheet + toast)
- IWish/Views/HomeView.swift (shared badge)
- IWish/Views/RootView.swift (TTL cleanup + toastOverlay)
- IWish/IWishApp.swift (Universal Links handling)
- IWish/IWish.entitlements (Associated Domains)

### QR (из предыдущей сессии, тоже в этом коде)
- IWish/Views/ShareWishlistSheet.swift — QR через dagronf/QRCode library
- IWish.xcodeproj/project.pbxproj — SPM dependency QRCode
