import CloudKit

@Observable
final class UserProfileService {
    enum DiscoverabilityStatus {
        case notAsked
        case askingCustom
        case askingSystem
        case granted
        case denied
    }

    var userName: String?
    var isLoading = false
    var discoverabilityStatus: DiscoverabilityStatus = .notAsked

    /// Start the discoverability flow: show custom modal first.
    func requestDiscoverability() {
        guard discoverabilityStatus == .notAsked else { return }

        let container = CKContainer(identifier: "iCloud.RUGyron.IWish")
        container.accountStatus { [weak self] status, _ in
            Task { @MainActor in
                guard let self else { return }
                guard status == .available else {
                    self.discoverabilityStatus = .denied
                    return
                }
                // Check if permission was already granted in a previous session
                container.status(forApplicationPermission: .userDiscoverability) { [weak self] permStatus, _ in
                    Task { @MainActor in
                        guard let self else { return }
                        if permStatus == .granted {
                            self.discoverabilityStatus = .granted
                            self.fetchProfile()
                        } else {
                            self.discoverabilityStatus = .askingCustom
                        }
                    }
                }
            }
        }
    }

    /// User pressed "Allow" in our custom modal — now call system API.
    func confirmCustomDialog() {
        discoverabilityStatus = .askingSystem

        let container = CKContainer(identifier: "iCloud.RUGyron.IWish")
        container.requestApplicationPermission(.userDiscoverability) { [weak self] permStatus, error in
            Task { @MainActor in
                guard let self else { return }
                print("[UserProfile] Discoverability permission: \(permStatus.rawValue), error: \(String(describing: error))")
                if permStatus == .granted {
                    self.discoverabilityStatus = .granted
                    self.fetchProfile()
                } else {
                    self.discoverabilityStatus = .denied
                }
            }
        }
    }

    /// User pressed "Not now" in our custom modal.
    func declineCustomDialog() {
        discoverabilityStatus = .denied
    }

    func fetchProfile() {
        guard userName == nil else { return }
        isLoading = true

        let container = CKContainer(identifier: "iCloud.RUGyron.IWish")

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
