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
    private static let iterations = 150_000

    private struct Record: Codable { let salt: Data; let hash: Data; let iterations: Int }

    private static var path: String {
        (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/HostsEditor/pin.json")
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

    static func verify(_ pin: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path),
              let record = try? JSONDecoder().decode(Record.self, from: data) else { return false }
        let candidate = digest(pin, salt: record.salt, rounds: record.iterations)
        // Constant-time compare so verification time doesn't leak how many bytes matched.
        guard candidate.count == record.hash.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(candidate, record.hash) { diff |= a ^ b }
        return diff == 0
    }

    static func clear() {
        try? FileManager.default.removeItem(atPath: path)
    }

    // Salt-prefixed SHA-256, iterated to make brute-forcing a short numeric PIN
    // costly even if the digest file leaks.
    private static func digest(_ pin: String, salt: Data, rounds: Int) -> Data {
        var acc = salt + Data(pin.utf8)
        for _ in 0..<max(1, rounds) { acc = Data(SHA256.hash(data: acc)) }
        return acc
    }
}
