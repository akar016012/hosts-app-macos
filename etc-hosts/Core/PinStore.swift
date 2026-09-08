// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import CryptoKit
import Foundation
import Security

// MARK: - PIN unlock

// An alternative to Touch ID for unlocking the edit session — useful on Macs
// without Touch ID, or when biometrics are unavailable/locked out. The PIN is
// never stored: only a random-salted, iterated SHA-256 digest in a 0600 file
// beside the signing key. Like Touch ID, the PIN is purely an app-level gate on
// `sessionUnlocked`; the privileged write itself is still authorized by the
// file-based signing key, so the PIN never weakens the helper's trust model.
enum PinStore {
    static let minLength = 4
    static let maxLength = 12
    static let maxAttempts = 5
    private static let iterations = 250_000

    private struct Record: Codable { let salt: Data; let hash: Data; let iterations: Int }
    // Persisted brute-force throttle: consecutive failures and an optional lockout
    // deadline. Kept beside the PIN digest (0600) so it survives relaunches.
    private struct Attempts: Codable { var failed: Int; var lockedUntil: Date? }

    // Outcome of a verify attempt: success, a wrong PIN (with attempts remaining
    // before lockout), or a lockout with the seconds left to wait.
    enum VerifyResult { case ok, wrong(remaining: Int), lockedOut(seconds: Int) }

    private static var path: String {
        (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/HostsEditor/pin.json")
    }
    private static var attemptsPath: String {
        (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/HostsEditor/pin-attempts.json")
    }

    static var isSet: Bool { FileManager.default.fileExists(atPath: path) }

    // MARK: Setup policy

    // Everything the "may a PIN be saved right now?" decision depends on, as
    // plain values so the rule is testable without the store or the UI.
    struct SetupContext {
        var pinSet: Bool
        var sessionUnlocked: Bool
        // The first-run walkthrough has finished at least once. A tour replay
        // flips it back, which is why this alone never marks a fresh install.
        var onboardingCompleted: Bool
        // A session signing key exists, i.e. some unlock (Touch ID, PIN, or the
        // macOS password) has already succeeded on this installation.
        var sessionKeyExists: Bool
        // A forgot-PIN reset backed by macOS authentication is still waiting
        // for its replacement PIN.
        var resetAuthorized: Bool
    }

    // Returns nil when saving a PIN is allowed, otherwise the user-facing reason.
    //
    // Changing an existing PIN always needs an unlocked session. Creating the
    // first PIN is allowed in exactly three situations, each of which already
    // proves the person at the keyboard owns the installation:
    //   - the session is unlocked;
    //   - a forgot-PIN reset just succeeded (macOS authentication);
    //   - the installation is genuinely fresh — onboarding has never finished
    //     and no session key exists — so there is no owner credential yet that
    //     a new PIN could sidestep.
    // Everything else, notably a locked, established install that never had a
    // PIN, is refused: otherwise anyone at the unlocked Mac could add a PIN of
    // their choosing and unlock Hosts with it.
    static func setupDenialReason(_ c: SetupContext) -> String? {
        if c.pinSet {
            return c.sessionUnlocked ? nil : "Unlock to change your PIN."
        }
        if c.sessionUnlocked || c.resetAuthorized { return nil }
        if !c.onboardingCompleted && !c.sessionKeyExists { return nil }
        return "Unlock with Touch ID or your macOS password to add a PIN."
    }

    // Returns a user-facing reason the PIN is unacceptable, or nil if it's valid.
    static func validate(_ pin: String) -> String? {
        guard pin.count >= minLength, pin.count <= maxLength, pin.allSatisfy(\.isNumber) else {
            return "PIN must be \(minLength)–\(maxLength) digits."
        }
        return nil
    }

    static func set(_ pin: String) throws {
        var salt = Data(count: 16)
        let ok = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard ok == errSecSuccess else { throw HostsError.failed("Couldn't save your PIN. Try again.") }

        let record = Record(salt: salt, hash: digest(pin, salt: salt, rounds: iterations), iterations: iterations)
        let data = try JSONEncoder().encode(record)
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        // Callers authenticate existing-PIN changes. Once the new PIN is saved,
        // it must not inherit failures or a lockout from the previous PIN.
        // Propagate reset failures so the caller cannot report a successful save.
        try saveAttempts(Attempts(failed: 0, lockedUntil: nil))
    }

    static func verify(_ pin: String) -> VerifyResult {
        var attempts = loadAttempts()
        // Honor an active lockout; an expired one is cleared but the failure count
        // is kept so repeated lockouts escalate the backoff.
        if let until = attempts.lockedUntil {
            if until > Date() {
                return .lockedOut(seconds: Int(until.timeIntervalSinceNow.rounded(.up)))
            }
            attempts.lockedUntil = nil
        }

        guard let data = FileManager.default.contents(atPath: path),
              let record = try? JSONDecoder().decode(Record.self, from: data) else {
            return .wrong(remaining: max(0, maxAttempts - attempts.failed))
        }
        let candidate = digest(pin, salt: record.salt, rounds: record.iterations)
        // Constant-time compare so verification time doesn't leak how many bytes matched.
        var diff: UInt8 = candidate.count == record.hash.count ? 0 : 1
        for (a, b) in zip(candidate, record.hash) { diff |= a ^ b }

        if diff == 0 {
            try? saveAttempts(Attempts(failed: 0, lockedUntil: nil))
            return .ok
        }

        attempts.failed += 1
        if attempts.failed >= maxAttempts {
            let backoff = lockoutSeconds(for: attempts.failed)
            attempts.lockedUntil = Date().addingTimeInterval(TimeInterval(backoff))
            try? saveAttempts(attempts)
            return .lockedOut(seconds: backoff)
        }
        try? saveAttempts(attempts)
        return .wrong(remaining: maxAttempts - attempts.failed)
    }

    // 30s after the first lockout, doubling on each further lockout, capped at 1h.
    private static func lockoutSeconds(for failed: Int) -> Int {
        let over = max(0, failed - maxAttempts)
        return min(30 * (1 << min(over, 7)), 3600)
    }

    private static func loadAttempts() -> Attempts {
        guard let data = FileManager.default.contents(atPath: attemptsPath),
              let a = try? JSONDecoder().decode(Attempts.self, from: data) else {
            return Attempts(failed: 0, lockedUntil: nil)
        }
        return a
    }

    private static func saveAttempts(_ a: Attempts) throws {
        let data = try JSONEncoder().encode(a)
        let dir = (attemptsPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: URL(fileURLWithPath: attemptsPath), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: attemptsPath)
    }

    static func clear() {
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.removeItem(atPath: attemptsPath)
    }

    // Salt-prefixed SHA-256, iterated to make brute-forcing a short numeric PIN
    // costly even if the digest file leaks.
    private static func digest(_ pin: String, salt: Data, rounds: Int) -> Data {
        var acc = salt + Data(pin.utf8)
        for _ in 0..<max(1, rounds) { acc = Data(SHA256.hash(data: acc)) }
        return acc
    }
}
