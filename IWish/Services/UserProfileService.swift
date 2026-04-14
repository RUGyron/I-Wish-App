import CloudKit
import UIKit

@Observable
final class UserProfileService {
    var userName: String?
    var isLoading = false

    func fetchProfile() {
        guard userName == nil else { return }
        isLoading = true

        let container = CKContainer.default()
        container.requestApplicationPermission(.userDiscoverability) { [weak self] status, _ in
            guard let self, status == .granted else {
                Task { @MainActor in
                    self?.isLoading = false
                    self?.userName = self?.deviceOwnerName()
                }
                return
            }

            container.fetchUserRecordID { [weak self] recordID, _ in
                guard let self, let recordID else {
                    Task { @MainActor in
                        self?.isLoading = false
                        self?.userName = self?.deviceOwnerName()
                    }
                    return
                }

                container.discoverUserIdentity(withUserRecordID: recordID) { [weak self] identity, _ in
                    Task { @MainActor in
                        self?.isLoading = false
                        if let name = identity?.nameComponents {
                            let fmt = PersonNameComponentsFormatter()
                            fmt.style = .default
                            self?.userName = fmt.string(from: name)
                        } else {
                            self?.userName = self?.deviceOwnerName()
                        }
                    }
                }
            }
        }
    }

    private func deviceOwnerName() -> String? {
        let name = UIDevice.current.name
        let lower = name.lowercased()
        for prefix in ["iphone ", "ipad ", "ipod "] {
            if lower.hasPrefix(prefix) {
                let stripped = String(name.dropFirst(prefix.count))
                if !stripped.isEmpty { return stripped }
            }
        }
        return name
    }
}
