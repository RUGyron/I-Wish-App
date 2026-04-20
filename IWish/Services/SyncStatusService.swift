import SwiftUI
import SwiftData
import CoreData
import CloudKit

@Observable
final class SyncStatusService {
    enum State: Equatable {
        case idle          // no sync activity
        case syncing       // sync in progress
        case synced(Date)  // last successful sync time
        case offline       // network unavailable
        case error(String) // sync failed with message
    }

    var state: State = .idle {
        didSet {
            if case .syncing = state {
                scheduleSyncTimeout()
            } else {
                cancelSyncTimeout()
            }
        }
    }
    var hasEverSynced: Bool = false

    private var retryTimer: Timer?
    private var syncTimeoutTimer: Timer?
    /// Debounce work item: delays .synced state so rapid successive syncs
    /// don't cause flickering between "Синхронизация..." and "Только что".
    private var syncedDebounce: DispatchWorkItem?

    init() {
        startListening()
        // Initial state: assume syncing until first event arrives
        state = .syncing
    }

    deinit {
        retryTimer?.invalidate()
        syncTimeoutTimer?.invalidate()
        syncedDebounce?.cancel()
    }

    private func scheduleSyncTimeout() {
        syncTimeoutTimer?.invalidate()
        syncTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            guard let self, case .syncing = self.state else { return }
            // No event received in 10s — treat as error
            self.state = .error("Нет ответа от iCloud")
            self.startRetryTimer()
        }
    }

    private func cancelSyncTimeout() {
        syncTimeoutTimer?.invalidate()
        syncTimeoutTimer = nil
    }

    /// Force a save on the context to nudge CloudKit into re-syncing.
    /// Only triggers if currently in error/offline state — otherwise no-op.
    func retry(context: ModelContext) {
        // No retry if already syncing or already synced successfully
        switch state {
        case .syncing, .synced, .idle: return
        case .error, .offline: break
        }
        state = .syncing
        try? context.save()
    }

    // MARK: - Listening

    private func startListening() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleEvent(notification)
        }
    }

    private func handleEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }

        if event.endDate == nil {
            // Event started — cancel any pending "synced" transition and show syncing
            syncedDebounce?.cancel()
            syncedDebounce = nil
            state = .syncing
            stopRetryTimer()
        } else if let error = event.error {
            // Event failed — cancel debounce and show error immediately
            syncedDebounce?.cancel()
            syncedDebounce = nil
            let ckError = error as NSError
            if ckError.domain == NSURLErrorDomain || ckError.code == CKError.networkUnavailable.rawValue || ckError.code == CKError.networkFailure.rawValue {
                state = .offline
            } else if let msg = (error as? CKError)?.errorUserInfo["ServerErrorDescription"] as? String {
                state = .error(msg)
            } else {
                state = .error(error.localizedDescription)
            }
            startRetryTimer()
        } else {
            // Event succeeded — debounce 0.4s: if another sync starts before the
            // deadline, the work item is cancelled and we stay in .syncing.
            // This prevents rapid "Синхронизация... → Только что → Синхронизация..."
            // flicker when CloudKit fires multiple sequential sync events.
            let finishDate = event.endDate ?? .now
            syncedDebounce?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.state = .synced(finishDate)
                self.hasEverSynced = true
                self.stopRetryTimer()
            }
            syncedDebounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
    }

    // MARK: - Auto-retry timer (5 s interval for error/offline)

    private func startRetryTimer() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Only keep retrying while in an error/offline state
            switch self.state {
            case .error, .offline:
                // Only transition if currently not syncing
                self.state = .syncing
                NotificationCenter.default.post(name: .syncRetryRequested, object: nil)
            default:
                self.stopRetryTimer()
            }
        }
    }

    private func stopRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = nil
    }
}

// MARK: - Notification name for retry

extension Notification.Name {
    static let syncRetryRequested = Notification.Name("SyncRetryRequested")
}
