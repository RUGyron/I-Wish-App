import CloudKit
import UIKit

@Observable
final class UserProfileService {
    var userName: String?
    var isLoading = false

    func fetchProfile() {
        guard userName == nil else { return }
        isLoading = true

        // Try CloudKit identity first
        let container = CKContainer(identifier: "iCloud.com.rugyron.iwish")
        container.fetchUserRecordID { [weak self] recordID, error in
            guard let self else { return }

            if let recordID, error == nil {
                container.discoverUserIdentity(withUserRecordID: recordID) { [weak self] identity, _ in
                    Task { @MainActor in
                        self?.isLoading = false
                        if let nameComponents = identity?.nameComponents {
                            let formatter = PersonNameComponentsFormatter()
                            formatter.style = .default
                            self?.userName = formatter.string(from: nameComponents)
                        } else {
                            // Fallback: device owner name
                            self?.userName = self?.deviceOwnerName()
                        }
                    }
                }
            } else {
                Task { @MainActor in
                    self.isLoading = false
                    self.userName = self.deviceOwnerName()
                }
            }
        }
    }

    private func deviceOwnerName() -> String? {
        let name = UIDevice.current.name
        let lower = name.lowercased()
        // "iPhone Владислава" → "Владислава"
        for prefix in ["iphone ", "ipad ", "ipod "] {
            if lower.hasPrefix(prefix) {
                let stripped = String(name.dropFirst(prefix.count))
                if !stripped.isEmpty { return stripped }
            }
        }
        // "iPhone" alone → return as-is (better than nil)
        return name
    }
}
