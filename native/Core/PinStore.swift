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
        guard ok == errSecSuccess else { throw HostsError.failed("Could not generate PIN salt.") }

        let record = Record(salt: salt, hash: digest(pin, salt: salt, rounds: iterations), iterations: iterations)
        let data = try JSONEncoder().encode(record)
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
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
            saveAttempts(Attempts(failed: 0, lockedUntil: nil))
            return .ok
        }

        attempts.failed += 1
        if attempts.failed >= maxAttempts {
            let backoff = lockoutSeconds(for: attempts.failed)
            attempts.lockedUntil = Date().addingTimeInterval(TimeInterval(backoff))
            saveAttempts(attempts)
            return .lockedOut(seconds: backoff)
        }
        saveAttempts(attempts)
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

    private static func saveAttempts(_ a: Attempts) {
        guard let data = try? JSONEncoder().encode(a) else { return }
        let dir = (attemptsPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? data.write(to: URL(fileURLWithPath: attemptsPath), options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: attemptsPath)
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
