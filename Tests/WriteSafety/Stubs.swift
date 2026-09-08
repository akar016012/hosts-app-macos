// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Foundation
import CryptoKit

// No service registration, credentials, authentication, sockets, or DNS probes.
enum ServiceManager {
    enum Status { case enabled, requiresApproval, unavailable }
    static let isEnabled = true
    static let status = Status.enabled
    static func registerIfNeeded() throws {}
    static func unregister() throws {}
    static func openLoginItems() {}
}
enum SigningKey {
    static let exists = false
    static func authenticate(reason: String) async throws {}
    static func ensureTouchIDAvailable() throws {}
}
@MainActor final class OnboardingStore {
    static let shared = OnboardingStore()
    var completed = true
}
enum HelperClient {
    static func isReady() -> Bool { true }
    static func prepare(resetSigningKey: Bool = false) throws {}
    static func runAdmin(_ command: String, prompt: String) throws {}
}

// Delay the actual helper writer to put an external edit between submission and
// persistence. It still compares and replaces real files, all under the test root.
actor HelperGateway {
    static let shared = HelperGateway()
    var path = ""
    var writes = 0
    var shouldFail = false
    func configure(path: String, fail: Bool = false) { self.path = path; shouldFail = fail }
    func count() -> Int { writes }
    func write(_ content: String, expectedContent: String) async throws {
        writes += 1
        try await Task.sleep(nanoseconds: 40_000_000)
        if shouldFail { throw HostsError.failed("Test write failed") }
        let hash = SHA256.hash(data: Data(expectedContent.utf8)).map { String(format: "%02x", $0) }.joined()
        do {
            try writeHostsFile(content: content, expectedHash: hash, path: path, backupDirectory: path + "-backups")
        } catch HostsFileConflict.changed {
            throw HostsError.fileConflict
        }
    }
}
