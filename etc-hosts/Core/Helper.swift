// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Foundation

// MARK: - Helper identifiers

// Protocol-level constants forward to Shared/HelperProtocol.swift (compiled into
// both the app and the daemon); only the app-private signing-key locations live
// here.
enum Helper {
    static let label = HelperProtocol.label
    static let protocolVersion = HelperProtocol.version
    static let plistName = HelperProtocol.plistName
    static let pubkeyPath = HelperProtocol.pubkeyPath
    static let uidPath = HelperProtocol.uidPath
    static let socketPath = HelperProtocol.socketPath
    static let keyTag = "com.etchosts.hostseditor.session-signing.v3".data(using: .utf8)!
    static let legacyKeyTags = [
        "com.etchosts.hostseditor.signing",
        "com.etchosts.hostseditor.session-signing.v2",
    ].map { $0.data(using: .utf8)! }
    // The session signing private key lives here (0600), NOT in the keychain.
    static let privateKeyPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent("Library/Application Support/HostsEditor/session-signing.key")
}
