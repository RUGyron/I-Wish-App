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

    init() {
        startListening()
        // Initial state: assume syncing until first event arrives
        state = .syncing
    }

    deinit {
        retryTimer?.invalidate()
        syncTimeoutTimer?.invalidate()
    }

    private func scheduleSyncTimeout() {
        syncTimeoutTimer?.invalidate()
        syncTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
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
    func retry(context: ModelContext) {
        guard state != .syncing else { return }
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
            // Event started
            state = .syncing
            stopRetryTimer()
        } else if let error = event.error {
            // Event failed
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
            // Event succeeded
            state = .synced(event.endDate ?? .now)
            hasEverSynced = true
            stopRetryTimer()
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
