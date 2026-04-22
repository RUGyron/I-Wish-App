# Firebase Sharing — Design Spec

**Дата:** 2026-04-22
**Заменяет:** CloudKit PublicDB sharing (2026-04-22), CKShare sharing (2026-04-18)

## Стек

- **Firebase Auth** — Sign in with Apple (анонимный апгрейд)
- **Firestore** — shared wishlists, items, memberships, invite links
- **SwiftData** — локальные (личные) вишлисты, offline-first

## Firestore Collections

```
wishlists/{wishlistID}
  ├── name: String
  ├── coverEmoji: String?
  ├── ownerUID: String (Firebase Auth UID)
  ├── ownerName: String?
  ├── createdAt: Timestamp
  ├── updatedAt: Timestamp
  └── items/ (subcollection)
        └── {itemID}
              ├── name: String
              ├── tier: String ("must"/"maybe"/"idea")
              ├── price: Double?
              ├── currency: String
              ├── url: String?
              ├── coverEmoji: String?
              ├── sortIndex: Double
              ├── isArchived: Bool
              ├── createdAt: Timestamp
              └── updatedAt: Timestamp

memberships/{membershipID}
  ├── wishlistID: String
  ├── userUID: String
  ├── role: String ("editor"/"viewer")
  └── joinedAt: Timestamp

inviteLinks/{shortID}
  ├── wishlistID: String
  ├── wishlistName: String
  ├── wishlistEmoji: String?
  ├── ownerName: String?
  ├── role: String
  ├── itemCount: Int
  ├── expiresAt: Timestamp?
  └── createdAt: Timestamp
```

## Auth Flow

1. При первом запуске — анонимный Firebase Auth (автоматический, без UI)
2. Если юзер хочет шарить — Sign in with Apple (upgrade anonymous → Apple)
3. UID стабилен, привязан к Apple ID
4. Имя из Apple ID credentials (givenName + familyName)

## Owner Share Flow

1. "Поделиться" → проверить auth (если anon → запросить Sign in with Apple)
2. Записать wishlist + items в Firestore wishlists/{id}
3. Создать inviteLinks/{shortID}
4. Показать QR / ссылку
5. Любые изменения → real-time sync в Firestore

## Receiver Accept Flow

1. Scan QR → resolve inviteLinks/{shortID}
2. InvitePreviewSheet с данными из invite
3. "Принять" → проверить auth → создать memberships/{id}
4. Snapshot listener на wishlists/{id} + items subcollection
5. Создать локальную копию в SwiftData (для offline)
6. Real-time updates через listener

## Real-time Sync

- `addSnapshotListener` на wishlists/{id}/items — мгновенные обновления
- При изменении локального shared item → write в Firestore
- При получении remote change → обновить локальный SwiftData
- Firestore offline persistence включена по умолчанию

## Security Rules

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Wishlists: owner can CRUD, members can read + write items
    match /wishlists/{wishlistID} {
      allow read: if isOwner() || isMember(wishlistID);
      allow create: if request.auth != null;
      allow update, delete: if isOwner();
      
      match /items/{itemID} {
        allow read: if isOwnerOfParent() || isMember(wishlistID);
        allow write: if isOwnerOfParent() || isEditor(wishlistID);
      }
    }
    
    // Memberships: creator can CRUD their own
    match /memberships/{membershipID} {
      allow read: if request.auth != null;
      allow create: if request.auth.uid == request.resource.data.userUID;
      allow delete: if request.auth.uid == resource.data.userUID;
    }
    
    // Invite links: owner creates, anyone authed reads
    match /inviteLinks/{shortID} {
      allow read: if request.auth != null;
      allow create, update, delete: if request.auth != null;
    }
    
    function isOwner() {
      return request.auth.uid == resource.data.ownerUID;
    }
    function isOwnerOfParent() {
      return request.auth.uid == get(/databases/$(database)/documents/wishlists/$(wishlistID)).data.ownerUID;
    }
    function isMember(wishlistID) {
      return exists(/databases/$(database)/documents/memberships/$(request.auth.uid + '_' + wishlistID));
    }
    function isEditor(wishlistID) {
      return get(/databases/$(database)/documents/memberships/$(request.auth.uid + '_' + wishlistID)).data.role == 'editor';
    }
  }
}
```

## Files

### Удаляем
- CloudKitSharingService.swift
- SharedWishlistSyncService.swift  
- SyncQueue.swift

### Создаём
- FirestoreService.swift — CRUD + listeners
- AuthService.swift — Sign in with Apple + Firebase Auth

### Модифицируем
- AppServices.swift — заменить sharing/syncQueue на firestore/auth
- ShareManager.swift — использовать FirestoreService
- JoinWishlistSheet.swift — использовать FirestoreService
- HomeView.swift — listener для shared wishlists
- WishlistDetailView.swift — listener для items
- ParticipantsView.swift — query memberships
- IWishApp.swift — Firebase.configure(), убрать CloudKit AppDelegate
- RootView.swift — убрать CloudKit subscription setup
</content>
</invoke>