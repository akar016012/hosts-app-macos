import Foundation
import SwiftUI

// MARK: - Local profile

// A lightweight, local-only identity for the app. There is no auth backend —
// "signing in" just means giving yourself a name (and optional email) so the
// header can show a personalized initials avatar and gather preferences and
// security controls under one Profile menu. Persisted in UserDefaults; the
// security primitives it surfaces (PIN, signing key) live in their own stores.
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    private static let nameKey = "hosts.profile.name"
    private static let emailKey = "hosts.profile.email"

    @Published var name: String {
        didSet { UserDefaults.standard.set(name, forKey: Self.nameKey) }
    }
    @Published var email: String {
        didSet { UserDefaults.standard.set(email, forKey: Self.emailKey) }
    }

    private init() {
        name = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
        email = UserDefaults.standard.string(forKey: Self.emailKey) ?? ""
    }

    // A profile is considered "signed in" once it has a name to show.
    var isSignedIn: Bool { !trimmedName.isEmpty }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    // Up to two letters: first letters of the first two words, else the first two
    // characters of a single word. Falls back to "?" so the avatar is never blank.
    var initials: String {
        let words = trimmedName.split(whereSeparator: { $0 == " " || $0 == "-" })
        let letters: [Character]
        if words.count >= 2 {
            letters = words.prefix(2).compactMap(\.first)
        } else if let first = words.first {
            letters = Array(first.prefix(2))
        } else {
            letters = []
        }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    func signOut() {
        name = ""
        email = ""
    }
}
