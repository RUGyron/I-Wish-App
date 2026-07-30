import SwiftUI

struct PrivacyDisclosureView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                    Text("Your data — yours only")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 32)

                Group {
                    section(
                        icon: "lock.fill",
                        title: String(localized: "Content is encrypted on device"),
                        body: String(localized: "List names, wishes, photos, prices, descriptions, links — everything is encrypted with AES-256 right on your iPhone before it flies to the cloud. Only unreadable bytes are stored on the server.")
                    )

                    section(
                        icon: "icloud.fill",
                        title: String(localized: "Keys live in iCloud Keychain"),
                        body: String(localized: "An encryption key for each list is generated locally and saved to iCloud Keychain. Apple syncs it between your Apple ID devices through an end-to-end secure channel. Apple sees keys only in encrypted form, the developer — never.")
                    )

                    section(
                        icon: "server.rack",
                        title: String(localized: "What we see in the cloud"),
                        body: String(localized: "Data is stored on Google Firebase. Through the Firebase console the developer can see only technical info: list counts, creation times, size of encrypted blobs, and “who shared with whom” links. The content itself — no.")
                    )

                    section(
                        icon: "person.text.rectangle",
                        title: String(localized: "Name in shared lists"),
                        body: String(localized: "If you share a list, your name is written to Firebase in plaintext in the membership document — so participants see each other’s real names. Without that they would show as an impersonal “Participant”. The name is not tied to list contents — the developer sees only the names themselves. If you don’t share lists, your name doesn’t end up in Firebase.")
                    )

                    section(
                        icon: "qrcode",
                        title: String(localized: "Sharing via QR code"),
                        body: String(localized: "When you share a list, the encryption key is embedded in the QR code or link (after `#`) and is not sent to the server. The recipient scans the QR — the key ends up on their device locally, and their iPhone decrypts the content itself.")
                    )

                    section(
                        icon: "exclamationmark.triangle.fill",
                        title: String(localized: "We don’t have a copy of your keys"),
                        body: String(localized: "If you lose all your Apple ID devices and reset iCloud Keychain — the data becomes unreadable forever. That’s the price for the developer never being able to peek inside.")
                    )

                    section(
                        icon: "eye.slash.fill",
                        title: String(localized: "No tracking or analytics"),
                        body: String(localized: "No analytics, crashlytics, ads. The app talks only to Firebase servers for sync (encrypted) and Apple for sign-in.")
                    )
                }
                .padding(.horizontal)

                VStack(spacing: 8) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("Source code is open and auditable")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(verbatim: "github.com/RUGyron/I-Wish-App")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, 16)
            }
        }
        .background(Theme.background)
        .navigationTitle("How we store your data")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(body).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
