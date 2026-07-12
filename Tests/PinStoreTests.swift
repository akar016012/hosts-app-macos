// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import CryptoKit
import Foundation
import Testing

// Touches pin.json / pin-attempts.json under NSHomeDirectory() and mutates shared
// lockout state — serialized, and guarded so it can only ever run against the
// scheme's throwaway CFFIXED_USER_HOME.
@Suite(.serialized) struct PinStoreTests {
    init() {
        requireTemporaryHome()
        PinStore.clear()
    }

    @Test func validation() {
        #expect(PinStore.validate("123") != nil, "validate: rejects too-short (3 digits)")
        #expect(PinStore.validate("1234567890123") != nil, "validate: rejects too-long (13 digits)")
        #expect(PinStore.validate("12ab") != nil, "validate: rejects non-numeric")
        #expect(PinStore.validate("") != nil, "validate: rejects empty")
        #expect(PinStore.validate("1234") == nil, "validate: accepts 4-digit PIN")
        #expect(PinStore.validate("123456789012") == nil, "validate: accepts 12-digit PIN")
    }

    @Test func setThenVerify() throws {
        try PinStore.set("4242")
        #expect(PinStore.isSet, "PinStore: isSet true after set")
        if case .ok = PinStore.verify("4242") {} else { Issue.record("verify: correct PIN should be .ok") }
    }

    // Ordering matters throughout — the whole lockout progression stays one test.
    @Test func lockoutProgression() throws {
        try PinStore.set("4242")
        // First wrong attempt -> remaining = maxAttempts - 1 = 4
        if case .wrong(let r1) = PinStore.verify("0000") {
            #expect(r1 == PinStore.maxAttempts - 1, "verify: 1st wrong -> remaining = maxAttempts-1")
        } else { Issue.record("verify: 1st wrong should be .wrong") }
        // Second wrong -> remaining decreases to 3
        if case .wrong(let r2) = PinStore.verify("0000") {
            #expect(r2 == PinStore.maxAttempts - 2, "verify: 2nd wrong -> remaining decreases")
        } else { Issue.record("verify: 2nd wrong should be .wrong") }
        // Attempts 3, 4 still wrong; attempt 5 (== maxAttempts) -> lockedOut
        _ = PinStore.verify("0000") // 3rd
        _ = PinStore.verify("0000") // 4th
        if case .lockedOut(let secs) = PinStore.verify("0000") {
            #expect(secs > 0, "verify: reaching maxAttempts -> .lockedOut with positive backoff")
        } else { Issue.record("verify: reaching maxAttempts should be .lockedOut") }
        // Document current behavior: while locked out, even the CORRECT PIN is
        // rejected with .lockedOut until the deadline passes.
        if case .lockedOut = PinStore.verify("4242") {} else {
            Issue.record("verify: correct PIN during lockout should return .lockedOut (current behavior)")
        }
    }

    @Test func clearResets() {
        PinStore.clear()
        #expect(!PinStore.isSet, "PinStore: isSet false after clear")
    }

    // clear() also wipes lockout/attempt state — the forgot-PIN reset path relies on
    // this so a locked-out user isn't still throttled after setting a new PIN.
    @Test func clearWipesLockoutState() throws {
        try PinStore.set("4242")
        for _ in 0..<PinStore.maxAttempts { _ = PinStore.verify("0000") } // drive into lockout
        if case .lockedOut = PinStore.verify("4242") {} else {
            Issue.record("clear: precondition failed — should be locked out before reset")
        }
        PinStore.clear()
        #expect(!PinStore.isSet, "clear: record gone after reset during lockout")
        try PinStore.set("7777")
        if case .wrong(let r) = PinStore.verify("0000") {
            #expect(r == PinStore.maxAttempts - 1, "clear: attempts state wiped — new PIN starts with full attempts")
        } else { Issue.record("clear: first wrong on new PIN should be .wrong (not lockedOut)") }
        if case .ok = PinStore.verify("7777") {} else {
            Issue.record("clear: new PIN should verify immediately after reset")
        }
    }

    @Test func clearIsIdempotent() {
        PinStore.clear()
        PinStore.clear()
        #expect(!PinStore.isSet, "clear: no-op when nothing is set")
    }

    // A pre-1.4 record (iterated SHA-256, no `kdf` field) must still verify, and a
    // successful verify must transparently rewrite it as PBKDF2-HMAC-SHA256.
    @Test func legacyRecordMigratesToPBKDF2() throws {
        PinStore.clear()
        let pin = "4242"
        let rounds = 2_000
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        // The legacy KDF: salt-prefixed SHA-256, iterated.
        var acc = salt + Data(pin.utf8)
        for _ in 0..<rounds { acc = Data(SHA256.hash(data: acc)) }

        // Hand-craft the legacy pin.json (no `kdf` key, like old builds wrote).
        struct LegacyRecord: Codable { let salt: Data; let hash: Data; let iterations: Int }
        let pinPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/HostsEditor/pin.json")
        try FileManager.default.createDirectory(atPath: (pinPath as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(LegacyRecord(salt: salt, hash: acc, iterations: rounds))
            .write(to: URL(fileURLWithPath: pinPath))

        #expect(PinStore.isSet, "migration: legacy record counts as a set PIN")
        if case .ok = PinStore.verify(pin) {} else {
            Issue.record("migration: legacy record should verify via the iterated-SHA256 path")
        }

        // The successful legacy verify rewrites the record under PBKDF2.
        let rewritten = try #require(FileManager.default.contents(atPath: pinPath),
                                     "migration: pin.json still exists after upgrade")
        let json = try #require(try JSONSerialization.jsonObject(with: rewritten) as? [String: Any])
        #expect(json["kdf"] as? String == "pbkdf2-hmac-sha256", "migration: rewritten record is PBKDF2")
        #expect(json["iterations"] as? Int == 600_000, "migration: rewritten record uses 600k rounds")

        // Second unlock now verifies through the PBKDF2 path.
        if case .ok = PinStore.verify(pin) {} else {
            Issue.record("migration: PIN should verify via PBKDF2 after the rewrite")
        }
        if case .wrong = PinStore.verify("0000") {} else {
            Issue.record("migration: wrong PIN should still be rejected after the rewrite")
        }
        PinStore.clear()
    }
}
