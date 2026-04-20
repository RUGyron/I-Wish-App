# CloudKit Sharing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement real CloudKit sharing so owners can create invite links via QR and receivers can join shared wishlists.

**Architecture:** CKShare in private DB for access control, ShareLink records in Public DB for shortID→CKShare URL mapping. Universal Links for deep linking from camera scans. SwiftData `.automatic` mode for transparent private/shared database routing.

**Tech Stack:** SwiftData, CloudKit (CKShare, CKRecord, CKContainer), QRCode library (already integrated), Universal Links, GitHub Pages (landing)

---

## File Structure

### New files
- `IWish/Services/CloudKitSharingService.swift` — CKShare lifecycle + PublicDB CRUD
- `IWish/Views/InvitePreviewSheet.swift` — invite preview UI for receiver

### Modified files
- `IWish/Services/ModelContainerFactory.swift` — `.private()` → `.automatic`
- `IWish/Services/ShareManager.swift` — rewrite with real CKShare + PublicDB
- `IWish/Services/AppServices.swift` — add CloudKitSharingService
- `IWish/Views/JoinWishlistSheet.swift` — resolve shortID → show InvitePreviewSheet
- `IWish/Views/HomeView.swift` — shared wishlist badge
- `IWish/IWishApp.swift` — Universal Link handling for incoming shares
- `IWish/IWish.entitlements` — add Associated Domains

### External files (not in Xcode project)
- GitHub Pages: `apple-app-site-association` + `index.html` landing

---

### Task 1: Entitlements & ModelContainerFactory

**Files:**
- Modify: `IWish/IWish.entitlements`
- Modify: `IWish/Services/ModelContainerFactory.swift`

- [ ] **Step 1: Add Associated Domains entitlement**

```xml
<!-- IWish/IWish.entitlements — add key before closing </dict> -->
<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:rugyron.github.io</string>
</array>
```

Full file after edit:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>aps-environment</key>
    <string>development</string>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.RUGyron.IWish</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
    <key>com.apple.developer.associated-domains</key>
    <array>
        <string>applinks:rugyron.github.io</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 2: Switch ModelContainerFactory to .automatic**

```swift
// IWish/Services/ModelContainerFactory.swift — full file replacement
import Foundation
import SwiftData

enum ModelContainerFactory {
    static let cloudKitContainerID = "iCloud.RUGyron.IWish"

    static func makeProductionContainer() -> ModelContainer {
        let schema = Schema([
            Wishlist.self,
            Item.self,
            AppSettings.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS,id=17A9B107-CE43-5472-9087-F1C57E8F1E58' -configuration Debug 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add IWish/IWish.entitlements IWish/Services/ModelContainerFactory.swift
git commit -m "feat: enable Associated Domains and automatic CloudKit database"
```

---

### Task 2: CloudKitSharingService

**Files:**
- Create: `IWish/Services/CloudKitSharingService.swift`

This is the core service that handles all CloudKit sharing operations.

- [ ] **Step 1: Create CloudKitSharingService**

```swift
// IWish/Services/CloudKitSharingService.swift
import CloudKit
import SwiftData
import CoreData

@Observable
final class CloudKitSharingService {
    private let containerID = "iCloud.RUGyron.IWish"
    private lazy var ckContainer = CKContainer(identifier: containerID)
    private let publicDB: CKDatabase
    private let recordType = "ShareLink"

    init() {
        let container = CKContainer(identifier: "iCloud.RUGyron.IWish")
        self.publicDB = container.publicCloudDatabase
    }

    // MARK: - Public DB: Create ShareLink

    func createShareLink(
        shortID: String,
        ckShareURL: URL,
        wishlistName: String,
        wishlistEmoji: String?,
        ownerName: String?,
        role: String,
        itemCount: Int,
        expiresAt: Date?
    ) async throws {
        let record = CKRecord(recordType: recordType)
        record["shortID"] = shortID as CKRecordValue
        record["ckShareURL"] = ckShareURL.absoluteString as CKRecordValue
        record["wishlistName"] = wishlistName as CKRecordValue
        if let emoji = wishlistEmoji { record["wishlistEmoji"] = emoji as CKRecordValue }
        if let name = ownerName { record["ownerName"] = name as CKRecordValue }
        record["role"] = role as CKRecordValue
        record["itemCount"] = itemCount as CKRecordValue
        if let exp = expiresAt { record["expiresAt"] = exp as CKRecordValue }

        try await publicDB.save(record)
    }

    // MARK: - Public DB: Resolve ShareLink by shortID

    struct ShareLinkInfo {
        let ckShareURL: URL
        let wishlistName: String
        let wishlistEmoji: String?
        let ownerName: String?
        let role: String
        let itemCount: Int
    }

    func resolveShareLink(shortID: String) async throws -> ShareLinkInfo? {
        let predicate = NSPredicate(format: "shortID == %@", shortID)
        let query = CKQuery(recordType: recordType, predicate: predicate)

        let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)
        guard let (_, result) = results.first,
              let record = try? result.get(),
              let urlString = record["ckShareURL"] as? String,
              let url = URL(string: urlString),
              let name = record["wishlistName"] as? String,
              let role = record["role"] as? String else {
            return nil
        }

        // Check expiry
        if let expiresAt = record["expiresAt"] as? Date, expiresAt < .now {
            return nil
        }

        return ShareLinkInfo(
            ckShareURL: url,
            wishlistName: name,
            wishlistEmoji: record["wishlistEmoji"] as? String,
            ownerName: record["ownerName"] as? String,
            role: role,
            itemCount: (record["itemCount"] as? Int) ?? 0
        )
    }

    // MARK: - Public DB: Delete ShareLink

    func deleteShareLink(shortID: String) async throws {
        let predicate = NSPredicate(format: "shortID == %@", shortID)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)

        for (recordID, _) in results {
            try await publicDB.deleteRecord(withID: recordID)
        }
    }

    // MARK: - Delete expired ShareLinks (TTL rotation)

    func deleteExpiredShareLinks() async {
        do {
            let predicate = NSPredicate(format: "expiresAt < %@", NSDate())
            let query = CKQuery(recordType: recordType, predicate: predicate)
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 50)

            for (recordID, _) in results {
                try? await publicDB.deleteRecord(withID: recordID)
            }
        } catch {
            print("[Sharing] Failed to clean expired links: \(error)")
        }
    }

    // MARK: - CKShare: Create

    func createShare(
        for wishlist: Wishlist,
        role: ShareRole,
        in container: ModelContainer
    ) async throws -> CKShare {
        // Access the underlying NSPersistentCloudKitContainer
        guard let coordinator = container.configurations.first?.url else {
            throw SharingError.containerNotAvailable
        }

        let persistentContainer = try getPersistentContainer(from: container)
        let objectID = try getObjectID(for: wishlist, in: persistentContainer)

        let (share, _) = try await persistentContainer.share([objectID], to: nil)

        // Configure share permissions
        share.publicPermission = role == .editor ? .readWrite : .readOnly

        // Save the share
        let modifyOp = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
        modifyOp.savePolicy = .changedKeys
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            modifyOp.modifyRecordsResultBlock = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let error): cont.resume(throwing: error)
                }
            }
            ckContainer.privateCloudDatabase.add(modifyOp)
        }

        return share
    }

    // MARK: - CKShare: Accept

    func acceptShare(from url: URL) async throws {
        let metadata = try await fetchShareMetadata(from: url)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let acceptOp = CKAcceptSharesOperation(shareMetadatas: [metadata])
            acceptOp.acceptSharesResultBlock = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let error): cont.resume(throwing: error)
                }
            }
            self.ckContainer.add(acceptOp)
        }
    }

    private func fetchShareMetadata(from url: URL) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { cont in
            let fetchOp = CKFetchShareMetadataOperation(shareURLs: [url])
            fetchOp.perShareMetadataResultBlock = { _, result in
                switch result {
                case .success(let metadata): cont.resume(returning: metadata)
                case .failure(let error): cont.resume(throwing: error)
                }
            }
            self.ckContainer.add(fetchOp)
        }
    }

    // MARK: - Helpers

    private func getPersistentContainer(from container: ModelContainer) throws -> NSPersistentCloudKitContainer {
        // SwiftData's ModelContainer wraps NSPersistentCloudKitContainer when cloudKitDatabase is set
        let mirror = Mirror(reflecting: container)
        for child in mirror.children {
            if let pc = child.value as? NSPersistentCloudKitContainer {
                return pc
            }
        }
        throw SharingError.containerNotAvailable
    }

    private func getObjectID(for wishlist: Wishlist, in container: NSPersistentCloudKitContainer) throws -> NSManagedObjectID {
        let context = container.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Wishlist")
        fetchRequest.predicate = NSPredicate(format: "id == %@", wishlist.id as CVarArg)
        fetchRequest.fetchLimit = 1

        guard let object = try context.fetch(fetchRequest).first else {
            throw SharingError.wishlistNotFound
        }
        return object.objectID
    }

    // MARK: - Errors

    enum SharingError: LocalizedError {
        case containerNotAvailable
        case wishlistNotFound
        case shareCreationFailed
        case invalidShareURL

        var errorDescription: String? {
            switch self {
            case .containerNotAvailable: return "Не удалось получить доступ к iCloud"
            case .wishlistNotFound: return "Список не найден"
            case .shareCreationFailed: return "Не удалось создать приглашение"
            case .invalidShareURL: return "Неверная ссылка приглашения"
            }
        }
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS,id=17A9B107-CE43-5472-9087-F1C57E8F1E58' -configuration Debug 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add IWish/Services/CloudKitSharingService.swift
git commit -m "feat: add CloudKitSharingService for CKShare and PublicDB operations"
```

---

### Task 3: Rewrite ShareManager

**Files:**
- Modify: `IWish/Services/ShareManager.swift`
- Modify: `IWish/Services/AppServices.swift`

- [ ] **Step 1: Add CloudKitSharingService to AppServices**

```swift
// IWish/Services/AppServices.swift — full file
import SwiftUI

@MainActor
final class AppServices {
    static let shared = AppServices()
    let syncStatus = SyncStatusService()
    let userProfile = UserProfileService()
    let sharing = CloudKitSharingService()
}

private struct AppServicesKey: EnvironmentKey {
    @MainActor
    static let defaultValue: AppServices = .shared
}

extension EnvironmentValues {
    var appServices: AppServices {
        get { self[AppServicesKey.self] }
        set { self[AppServicesKey.self] = newValue }
    }
}
```

- [ ] **Step 2: Rewrite ShareManager with real CloudKit**

```swift
// IWish/Services/ShareManager.swift — full file
import CloudKit
import SwiftUI
import SwiftData

// MARK: - Share Role

enum ShareRole: String, CaseIterable, Identifiable {
    case editor
    case viewer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .editor: return "Редактор"
        case .viewer: return "Только просмотр"
        }
    }
}

// MARK: - Share Manager

@Observable
final class ShareManager {
    private(set) var shareURL: URL?
    private(set) var expiresAt: Date?
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var shortID: String?

    private static let linkDomain = "https://rugyron.github.io/I-Wish-App"
    private let sharingService = CloudKitSharingService()

    func generateShare(
        for wishlist: Wishlist,
        role: ShareRole,
        ttl: InviteTTL,
        ownerName: String?,
        container: ModelContainer
    ) async {
        isLoading = true
        error = nil

        do {
            // 1. Create CKShare
            let share = try await sharingService.createShare(for: wishlist, role: role, in: container)

            guard let ckShareURL = share.url else {
                throw CloudKitSharingService.SharingError.shareCreationFailed
            }

            // 2. Generate shortID
            let newShortID = wishlist.id.uuidString
                .replacingOccurrences(of: "-", with: "")
                .prefix(12)
                .lowercased()

            // 3. Create ShareLink in Public DB
            let itemCount = (wishlist.items ?? []).filter { !$0.isArchived }.count
            let expiry = ttl.duration.map { Date.now.addingTimeInterval($0) }

            try await sharingService.createShareLink(
                shortID: String(newShortID),
                ckShareURL: ckShareURL,
                wishlistName: wishlist.name,
                wishlistEmoji: wishlist.coverEmoji,
                ownerName: ownerName,
                role: role.rawValue,
                itemCount: itemCount,
                expiresAt: expiry
            )

            // 4. Generate user-facing URL
            let url = URL(string: "\(Self.linkDomain)/j/\(newShortID)")!

            self.shareURL = url
            self.expiresAt = expiry
            self.shortID = String(newShortID)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func revokeAll() async {
        if let shortID {
            try? await sharingService.deleteShareLink(shortID: shortID)
        }
        shareURL = nil
        expiresAt = nil
        shortID = nil
        error = nil
    }

    var hasActiveShare: Bool { shareURL != nil }

    func invitationText(wishlistName: String) -> String {
        guard let url = shareURL else { return "" }
        return "Присоединяйся к моему списку желаний «\(wishlistName)» в I Wish!\n\n\(url.absoluteString)"
    }
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS,id=17A9B107-CE43-5472-9087-F1C57E8F1E58' -configuration Debug 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"`
Expected: BUILD FAILED (ShareWishlistSheet still calls old API)

- [ ] **Step 4: Update ShareWishlistSheet to use new async API**

The `ShareWishlistSheet` currently calls `shareManager.generateShare(for:role:ttl:)` synchronously. We need to update all call sites to use the new async version:

Find and replace all calls to `generateShare` in ShareWishlistSheet.swift:

Replace the `onAppear`/`onChange` calls that look like:
```swift
shareManager.generateShare(for: wishlist, role: selectedRole, ttl: selectedTTL)
```

With:
```swift
Task {
    await shareManager.generateShare(
        for: wishlist,
        role: selectedRole,
        ttl: selectedTTL,
        ownerName: services.userProfile.userName,
        container: container
    )
}
```

This requires adding to ShareWishlistSheet:
```swift
@Environment(\.modelContext) private var modelContext
@Environment(\.appServices) private var services
```

And getting the container from the environment. Since `modelContext.container` is available in SwiftData, use that.

Also update `revokeAll()` calls:
```swift
// Old:
shareManager.revokeAll()
// New:
Task { await shareManager.revokeAll() }
```

- [ ] **Step 5: Build and verify**

Run: `xcodebuild -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS,id=17A9B107-CE43-5472-9087-F1C57E8F1E58' -configuration Debug 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add IWish/Services/ShareManager.swift IWish/Services/AppServices.swift IWish/Views/ShareWishlistSheet.swift
git commit -m "feat: rewrite ShareManager with real CKShare and PublicDB"
```

---

### Task 4: InvitePreviewSheet

**Files:**
- Create: `IWish/Views/InvitePreviewSheet.swift`

- [ ] **Step 1: Create InvitePreviewSheet**

```swift
// IWish/Views/InvitePreviewSheet.swift
import SwiftUI

struct InvitePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let info: CloudKitSharingService.ShareLinkInfo
    let onAccept: () -> Void

    @State private var isAccepting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Hero
                VStack(spacing: 8) {
                    if let emoji = info.wishlistEmoji, !emoji.isEmpty {
                        Text(emoji)
                            .font(.system(size: 56))
                    } else {
                        Image(systemName: "list.star")
                            .font(.system(size: 48))
                            .foregroundStyle(.tint)
                    }

                    Text(info.wishlistName)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)

                // Invite details
                VStack(spacing: 12) {
                    if let ownerName = info.ownerName, !ownerName.isEmpty {
                        Label("\(ownerName) приглашает тебя", systemImage: "person.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Label(
                        info.role == "editor" ? "Роль: Редактор" : "Только просмотр",
                        systemImage: info.role == "editor" ? "pencil" : "eye"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if info.itemCount > 0 {
                        Label(
                            "\(info.itemCount) \(itemWord(info.itemCount)) в списке",
                            systemImage: "gift"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Actions
                VStack(spacing: 12) {
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }

                    Button {
                        isAccepting = true
                        onAccept()
                    } label: {
                        if isAccepting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Принять приглашение")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isAccepting)

                    Button("Отклонить") {
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("Приглашение")
            .navigationBarTitleDisplayMode(.inline)
            .fontDesign(.rounded)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    private func itemWord(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "желание" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "желания" }
        return "желаний"
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS,id=17A9B107-CE43-5472-9087-F1C57E8F1E58' -configuration Debug 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add IWish/Views/InvitePreviewSheet.swift
git commit -m "feat: add InvitePreviewSheet for incoming share invitations"
```

---

### Task 5: Receiver Flow — JoinWishlistSheet

**Files:**
- Modify: `IWish/Views/JoinWishlistSheet.swift`

- [ ] **Step 1: Rewrite joinByLink with real Public DB resolution + InvitePreviewSheet**

Replace the `JoinWishlistSheet` struct with updated version that:
1. Parses shortID from scanned URL (keep existing URL parsing)
2. Queries Public DB via `CloudKitSharingService.resolveShareLink(shortID:)`
3. Shows `InvitePreviewSheet` with the resolved info
4. On accept: calls `CloudKitSharingService.acceptShare(from:)`

Key changes to the struct:

Add new state properties:
```swift
@Environment(\.appServices) private var services
@State private var resolvedInfo: CloudKitSharingService.ShareLinkInfo?
@State private var showingInvitePreview = false
```

Rewrite `joinByLink(_ link: String)`:
```swift
private func joinByLink(_ link: String) {
    let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed) else {
        joinStatus = .error("Неверная ссылка")
        return
    }

    let shortID: String?
    let host = url.host() ?? ""
    let path = url.path()

    if url.scheme == "https",
       host.contains("rugyron.github.io"),
       let jRange = path.range(of: "/j/") {
        let after = path[jRange.upperBound...]
        let id = String(after.prefix(while: { $0 != "/" && $0 != "?" }))
        shortID = id.isEmpty ? nil : id
    } else if url.scheme == "iwish", url.host() == "join" {
        shortID = url.pathComponents.last.flatMap { $0.isEmpty ? nil : $0 }
    } else {
        shortID = nil
    }

    guard let id = shortID else {
        joinStatus = .error("Неверная ссылка")
        return
    }

    joinStatus = .joining

    Task {
        do {
            guard let info = try await services.sharing.resolveShareLink(shortID: id) else {
                joinStatus = .error("Приглашение недействительно или истекло")
                return
            }
            resolvedInfo = info
            joinStatus = .idle
            showingInvitePreview = true
        } catch {
            joinStatus = .error("Не удалось загрузить приглашение")
        }
    }
}
```

Add `acceptInvite()` method:
```swift
private func acceptInvite() {
    guard let info = resolvedInfo else { return }
    Task {
        do {
            try await services.sharing.acceptShare(from: info.ckShareURL)
            showingInvitePreview = false
            joinStatus = .success(info.wishlistName)
            try? await Task.sleep(for: .seconds(1.5))
            dismiss()
        } catch {
            joinStatus = .error("Не удалось присоединиться. Попробуйте ещё раз")
            showingInvitePreview = false
        }
    }
}
```

Add `.sheet` modifier for InvitePreviewSheet in body:
```swift
.sheet(isPresented: $showingInvitePreview) {
    if let info = resolvedInfo {
        InvitePreviewSheet(info: info) {
            acceptInvite()
        }
        .presentationDetents([.medium])
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS,id=17A9B107-CE43-5472-9087-F1C57E8F1E58' -configuration Debug 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add IWish/Views/JoinWishlistSheet.swift
git commit -m "feat: JoinWishlistSheet resolves shortID via PublicDB and shows InvitePreviewSheet"
```

---

### Task 6: Universal Links handling in IWishApp

**Files:**
- Modify: `IWish/IWishApp.swift`

- [ ] **Step 1: Add Universal Link handling + share acceptance**

Update `IWishApp.swift`:

1. Add state for incoming share URL:
```swift
@State private var pendingShareURL: String?
@State private var showingJoinFromLink = false
```

2. Add `onOpenURL` handler that also handles `https://rugyron.github.io/I-Wish-App/j/...` Universal Links:
```swift
.onOpenURL { url in
    if url.scheme == "https",
       (url.host() ?? "").contains("rugyron.github.io"),
       url.path().contains("/j/") {
        // Universal Link — trigger join flow
        pendingShareURL = url.absoluteString
        showingJoinFromLink = true
    } else {
        handleIncomingURL(url)
    }
}
```

3. Add sheet for auto-triggered join:
```swift
.sheet(isPresented: $showingJoinFromLink) {
    JoinWishlistSheet(initialURL: pendingShareURL)
}
```

4. Update `JoinWishlistSheet` to accept optional `initialURL` parameter — if provided, auto-trigger `joinByLink` on appear.

Add to JoinWishlistSheet:
```swift
var initialURL: String? = nil
```

In body, add:
```swift
.onAppear {
    if let url = initialURL {
        joinByLink(url)
    }
}
```

- [ ] **Step 2: Also handle `userDidAcceptCloudKitShare` for direct CKShare URLs**

Add to IWishApp body scene:
```swift
WindowGroup {
    RootView()
        .environment(\.appServices, .shared)
        .onOpenURL { url in ... }
}
.modelContainer(container)
.onChange(of: scenePhase) { ... } // optional: TTL check
```

For CloudKit share acceptance via system (when user taps iCloud share link directly), SwiftData handles this automatically with `.automatic` configuration — no additional code needed.

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS,id=17A9B107-CE43-5472-9087-F1C57E8F1E58' -configuration Debug 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add IWish/IWishApp.swift IWish/Views/JoinWishlistSheet.swift
git commit -m "feat: handle Universal Links for incoming share invitations"
```

---

### Task 7: HomeView shared wishlist badge

**Files:**
- Modify: `IWish/Views/HomeView.swift`

- [ ] **Step 1: Add shared badge to wishlist cards**

Find the wishlist card/row in HomeView and add a badge for shared wishlists. Look for the view that displays `wishlist.name` in the list.

Add after the wishlist name/subtitle:
```swift
if wishlist.isShared {
    Label("Общий", systemImage: "person.2.fill")
        .font(.caption2)
        .foregroundStyle(.secondary)
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS,id=17A9B107-CE43-5472-9087-F1C57E8F1E58' -configuration Debug 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add IWish/Views/HomeView.swift
git commit -m "feat: show shared badge on shared wishlists in HomeView"
```

---

### Task 8: TTL rotation on app launch

**Files:**
- Modify: `IWish/Views/RootView.swift`

- [ ] **Step 1: Add TTL check on appear**

Add to RootView:
```swift
@Environment(\.appServices) private var services
```

In body, add `.task` modifier:
```swift
.task {
    await services.sharing.deleteExpiredShareLinks()
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS,id=17A9B107-CE43-5472-9087-F1C57E8F1E58' -configuration Debug 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add IWish/Views/RootView.swift
git commit -m "feat: clean expired share links on app launch"
```

---

### Task 9: GitHub Pages — AASA + Landing

**Files:**
- External: GitHub Pages repo `rugyron.github.io` (or `I-Wish-App` repo GitHub Pages)

- [ ] **Step 1: Create apple-app-site-association file**

Create `.well-known/apple-app-site-association` (no file extension) at the root of GitHub Pages:

```json
{
    "applinks": {
        "apps": [],
        "details": [
            {
                "appID": "N8VX7T6P4D.RUGyron.IWish",
                "paths": ["/I-Wish-App/j/*"]
            }
        ]
    }
}
```

Note: `N8VX7T6P4D` is the Team ID from the Xcode project (found in build settings `DEVELOPMENT_TEAM`).

- [ ] **Step 2: Create fallback landing page**

Create `I-Wish-App/j/index.html`:

```html
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>I Wish — Присоединиться к списку</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            background: #f5f0eb;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            padding: 24px;
        }
        .card {
            background: white;
            border-radius: 24px;
            padding: 48px 32px;
            text-align: center;
            max-width: 400px;
            width: 100%;
            box-shadow: 0 4px 24px rgba(0,0,0,0.08);
        }
        .logo { font-size: 64px; margin-bottom: 16px; }
        h1 { font-size: 24px; font-weight: 700; margin-bottom: 8px; }
        p { color: #666; font-size: 16px; margin-bottom: 32px; line-height: 1.5; }
        .btn {
            display: inline-block;
            background: #b8610f;
            color: white;
            text-decoration: none;
            padding: 16px 32px;
            border-radius: 14px;
            font-size: 17px;
            font-weight: 600;
        }
    </style>
</head>
<body>
    <div class="card">
        <div class="logo">🎁</div>
        <h1>I Wish</h1>
        <p>Тебя пригласили в список желаний.<br>Скачай приложение, чтобы присоединиться.</p>
        <a class="btn" href="https://apps.apple.com/app/i-wish/idXXXXXXXXXX">
            Открыть в App Store
        </a>
    </div>
</body>
</html>
```

Replace `idXXXXXXXXXX` with the actual App Store ID when the app is published. Until then, the link can point to the App Store main page.

- [ ] **Step 3: Push to GitHub Pages and verify AASA**

After pushing, verify AASA is served correctly:
```bash
curl -I https://rugyron.github.io/.well-known/apple-app-site-association
```
Expected: HTTP 200, content-type application/json

- [ ] **Step 4: Commit (in IWish repo — document the external dependency)**

No code changes in IWish repo for this task. The GitHub Pages setup is external.

---

### Task 10: Integration test on device

- [ ] **Step 1: Build and install on primary device**

```bash
xcodebuild -project IWish.xcodeproj -scheme IWish -destination 'platform=iOS,id=17A9B107-CE43-5472-9087-F1C57E8F1E58' -configuration Debug 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
xcrun devicectl device install app --device 17A9B107-CE43-5472-9087-F1C57E8F1E58 "..."
xcrun devicectl device process launch --device 17A9B107-CE43-5472-9087-F1C57E8F1E58 RUGyron.IWish
```

- [ ] **Step 2: Test Owner flow**
1. Create a wishlist with a few items
2. Swipe → "Поделиться"
3. Verify QR appears after loading (not instant)
4. Copy link → verify it's `https://rugyron.github.io/I-Wish-App/j/{shortID}`

- [ ] **Step 3: Test Receiver flow (simulator or second device)**
1. Open app on second device/simulator
2. "Присоединиться" → "Вставить из буфера" (paste the copied link)
3. Verify InvitePreviewSheet appears with correct wishlist name, owner, role
4. Tap "Принять"
5. Verify shared wishlist appears in HomeView

- [ ] **Step 4: Test error cases**
1. Paste expired/invalid link → verify "Приглашение недействительно или истекло"
2. Paste garbage string → verify "Неверная ссылка"
3. Revoke share → try joining with old link → verify it fails gracefully
