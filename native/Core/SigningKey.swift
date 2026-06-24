// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Foundation
import LocalAuthentication
import Security

// MARK: - Session signing key

enum SigningKey {
    // The session signing key is an EC P-256 private key persisted as a 0600 file
    // in the user's Application Support directory — NOT in the keychain. A
    // keychain-stored key gates each use with an ACL bound to the app's code
    // signature; for an ad-hoc-signed app that identity changes on every rebuild,
    // so macOS prompts for the keychain password on every signature. A file-based
    // key has no ACL and never prompts. Editing is gated by the per-session
    // Touch ID unlock and the key file's 0600 owner-only permissions.

    static func existing() -> SecKey? {
        guard let data = FileManager.default.contents(atPath: Helper.privateKeyPath) else { return nil }
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        return SecKeyCreateWithData(data as CFData, attrs as CFDictionary, nil)
    }

    static func deleteExisting() {
        try? FileManager.default.removeItem(atPath: Helper.privateKeyPath)
        // Clean up keys left in the legacy keychain by older builds.
        for tag in [Helper.keyTag] + Helper.legacyKeyTags {
            let q: [String: Any] = [
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: tag,
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecUseDataProtectionKeychain as String: false,
            ]
            SecItemDelete(q as CFDictionary)
        }
    }

    private static func touchIDUnavailableMessage(_ error: Error?) -> String {
        guard let error else { return "Touch ID is not available on this Mac." }
        let nsError = error as NSError
        guard nsError.domain == LAError.errorDomain, let code = LAError.Code(rawValue: nsError.code) else {
            return "Touch ID isn't available right now. Set it up in System Settings, then try again."
        }
        switch code {
        case .biometryNotAvailable:
            return "Touch ID is not available on this Mac."
        case .biometryNotEnrolled:
            return "Set up Touch ID in System Settings before enabling Hosts session unlock."
        case .biometryLockout:
            return "Touch ID is locked. Unlock it in System Settings or with your login password, then try again."
        case .passcodeNotSet:
            return "Set a login password before using Touch ID session unlock."
        default:
            return "Touch ID isn't available right now. Set it up in System Settings, then try again."
        }
    }

    private static func touchIDError(_ error: Error) -> HostsError {
        let nsError = error as NSError
        if nsError.domain == LAError.errorDomain, let code = LAError.Code(rawValue: nsError.code) {
            switch code {
            case .userCancel, .appCancel, .systemCancel:
                return .cancelled
            case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout, .passcodeNotSet:
                return .failed(touchIDUnavailableMessage(error))
            default:
                break
            }
        }
        return .failed("Couldn't confirm Touch ID. Try again.")
    }

    static func ensureTouchIDAvailable() throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error),
              context.biometryType == .touchID else {
            throw HostsError.failed(touchIDUnavailableMessage(error))
        }
    }

    static func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedReason = reason
        context.localizedFallbackTitle = ""

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error),
              context.biometryType == .touchID else {
            throw HostsError.failed(touchIDUnavailableMessage(error))
        }

        do {
            try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            throw touchIDError(error)
        }
    }

    @discardableResult
    static func getOrCreate() throws -> SecKey {
        if let k = existing() { return k }
        try ensureTouchIDAvailable()
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var err: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attrs as CFDictionary, &err) else {
            throw HostsError.failed("Couldn't set up secure unlock. Reopen Hosts and try again.")
        }
        guard let data = SecKeyCopyExternalRepresentation(key, &err) as Data? else {
            throw HostsError.failed("Couldn't set up secure unlock. Reopen Hosts and try again.")
        }
        try persist(data)
        return key
    }

    // Writes the private key bytes to a 0600 file in a 0700 directory.
    private static func persist(_ data: Data) throws {
        let dir = (Helper.privateKeyPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: URL(fileURLWithPath: Helper.privateKeyPath), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: Helper.privateKeyPath)
    }

    static func publicKeyData(resetExistingKey: Bool = false) throws -> Data {
        if resetExistingKey { deleteExisting() }
        let key = try getOrCreate()
        guard let pub = SecKeyCopyPublicKey(key) else {
            throw HostsError.failed("Couldn't set up secure unlock. Reopen Hosts and try again.")
        }
        var err: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(pub, &err) as Data? else {
            throw HostsError.failed("Couldn't set up secure unlock. Reopen Hosts and try again.")
        }
        return data
    }

    // Read-only: returns the current key's public bytes, or nil if no key exists.
    // Unlike publicKeyData() this never creates a key or prompts for Touch ID, so
    // it is safe to call from readiness checks like HelperClient.needsEnroll().
    static func existingPublicKeyData() -> Data? {
        guard let key = existing(),
              let pub = SecKeyCopyPublicKey(key),
              let data = SecKeyCopyExternalRepresentation(pub, nil) as Data? else { return nil }
        return data
    }

    static func sign(_ data: Data) throws -> Data {
        guard let key = existing() else {
            throw HostsError.failed("Secure unlock was reset. Lock Hosts, then unlock again to continue.")
        }
        var err: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, data as CFData, &err) as Data? else {
            if let e = err?.takeRetainedValue() {
                let code = CFErrorGetCode(e)
                if code == errSecUserCanceled || code == LAError.userCancel.rawValue || code == -2 {
                    throw HostsError.cancelled
                }
            }
            throw HostsError.failed("Couldn't confirm your unlock. Lock Hosts, then unlock again.")
        }
        return sig
    }
}
