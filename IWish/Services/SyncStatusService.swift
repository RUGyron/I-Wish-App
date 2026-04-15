import SwiftUI
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

    var state: State = .idle

    init() {
        startListening()
    }

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
        } else {
            // Event succeeded
            state = .synced(event.endDate ?? .now)
        }
    }
}
