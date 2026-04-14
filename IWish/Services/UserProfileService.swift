import CloudKit

@Observable
final class UserProfileService {
    var userName: String?
    var isLoading = false

    func fetchProfile() {
        guard userName == nil else { return }
        isLoading = true

        let container = CKContainer.default()
        container.fetchUserRecordID { [weak self] recordID, error in
            guard let self, let recordID, error == nil else {
                Task { @MainActor in
                    self?.isLoading = false
                    self?.userName = nil
                }
                return
            }

            container.discoverUserIdentity(withUserRecordID: recordID) { [weak self] identity, error in
                Task { @MainActor in
                    self?.isLoading = false
                    if let nameComponents = identity?.nameComponents {
                        let formatter = PersonNameComponentsFormatter()
                        formatter.style = .default
                        self?.userName = formatter.string(from: nameComponents)
                    }
                }
            }
        }
    }
}
