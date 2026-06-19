import Foundation

// MARK: - Helper identifiers (must match HostsHelper / build.sh)

enum Helper {
    static let label = "com.aditya.hostshelper"
    static let toolPath = "/Library/PrivilegedHelperTools/com.aditya.hostshelper"
    static let plistPath = "/Library/LaunchDaemons/com.aditya.hostshelper.plist"
    static let pubkeyPath = "/Library/Application Support/HostsHelper/pubkey"
    // The uid authorized to drive the daemon, written at install time. The daemon
    // rejects connections from any other (non-root) user.
    static let uidPath = "/Library/Application Support/HostsHelper/uid"
    static let socketPath = "/var/run/com.aditya.hostshelper.sock"
    static let keyTag = "com.aditya.hostseditor.session-signing.v3".data(using: .utf8)!
    static let legacyKeyTags = [
        "com.aditya.hostseditor.signing",
        "com.aditya.hostseditor.session-signing.v2",
    ].map { $0.data(using: .utf8)! }
    // The session signing private key lives here (0600), NOT in the keychain.
    static let privateKeyPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent("Library/Application Support/HostsEditor/session-signing.key")
}
