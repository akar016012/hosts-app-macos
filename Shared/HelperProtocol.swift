// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Foundation

// MARK: - App ↔ helper wire protocol

// The single source of truth for the constants and canonical byte format the app
// and the privileged daemon must agree on. This file is compiled into BOTH targets
// (and the test bundle), so the two sides can no longer drift apart. Keep it pure
// declarations — the daemon's main.swift is top-level code, and a shared file with
// top-level statements would not compile there.
enum HelperProtocol {
    // Wire-protocol version. Bump whenever the request/reply format changes.
    static let version = 1
    static let label = "com.etchosts.hostshelper"
    // The launchd plist bundled at Contents/Library/LaunchDaemons/<plistName>; its
    // file-name stem must equal `label`.
    static let plistName = "com.etchosts.hostshelper.plist"
    static let socketPath = "/var/run/com.etchosts.hostshelper.sock"
    // Enrolled trust anchor: the app's signing public key and the uid authorized
    // to drive the daemon, both persisted root-owned by the daemon at enroll time.
    static let pubkeyPath = "/Library/Application Support/HostsHelper/pubkey"
    static let uidPath = "/Library/Application Support/HostsHelper/uid"
    // Bundle identifier the daemon's peer code-signature check requires.
    static let clientBundleID = "com.etchosts.hostseditor"

    // The exact bytes signed by the app and verified by the daemon for a write.
    // Both sides MUST produce identical output for identical inputs.
    static func canonicalMessage(ts: Int, nonce: String, contentB64: String) -> Data {
        Data("hostshelper-v1\n\(ts)\n\(nonce)\n\(contentB64)".utf8)
    }
}
