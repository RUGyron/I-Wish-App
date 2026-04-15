import CloudKit

@Observable
final class UserProfileService {
    var userName: String?
    var isLoading = false

    func fetchProfile() {
        guard userName == nil else { return }
        isLoading = true

        let container = CKContainer(identifier: "iCloud.RUGyron.IWish")

        // Check account status first
        container.accountStatus { [weak self] status, error in
            guard let self else { return }

            if status != .available {
                print("[UserProfile] iCloud account not available: \(status.rawValue), error: \(String(describing: error))")
                Task { @MainActor in
                    self.isLoading = false
                    // No name, greeting will show "Привет!" without name
                }
                return
            }

            // Request discoverability
            container.requestApplicationPermission(.userDiscoverability) { [weak self] permStatus, error in
                guard let self else { return }
                print("[UserProfile] Discoverability permission: \(permStatus.rawValue), error: \(String(describing: error))")

                guard permStatus == .granted else {
                    Task { @MainActor in
                        self.isLoading = false
                    }
                    return
                }

                container.fetchUserRecordID { [weak self] recordID, error in
                    guard let self, let recordID else {
                        print("[UserProfile] fetchUserRecordID failed: \(String(describing: error))")
                        Task { @MainActor in self?.isLoading = false }
                        return
                    }

                    container.discoverUserIdentity(withUserRecordID: recordID) { [weak self] identity, error in
                        Task { @MainActor in
                            self?.isLoading = false
                            if let name = identity?.nameComponents {
                                let fmt = PersonNameComponentsFormatter()
                                fmt.style = .default
                                self?.userName = fmt.string(from: name)
                                print("[UserProfile] Got name: \(self?.userName ?? "nil")")
                            } else {
                                print("[UserProfile] No identity: \(String(describing: error))")
                            }
                        }
                    }
                }
            }
        }
    }
}
