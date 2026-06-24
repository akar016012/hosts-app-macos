// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Darwin
import Foundation

// MARK: - Write serializer

// Serializes privileged writes and runs them off the main actor. Each call to
// the daemon is a blocking socket round-trip; funneling every write through one
// actor guarantees they can't interleave (which could write the file in a stale
// order or tear a backup) and keeps the blocking IO off the UI thread.
actor HelperGateway {
    static let shared = HelperGateway()
    func write(_ content: String) throws {
        try HelperClient.write(content: content)
    }
}

// MARK: - Privileged helper client

enum HelperClient {
    static func isResponding() -> Bool {
        guard let fd = connect() else { return false }
        close(fd)
        return true
    }

    // Fully ready to accept writes: daemon registered + enabled, socket answering,
    // and our current signing key is the one it trusts.
    static func isReady() -> Bool {
        ServiceManager.isEnabled && isResponding() && !needsEnroll()
    }

    // True if the daemon's recorded public key doesn't match our current signing key
    // (or none is recorded yet), meaning we must (re-)enroll. The daemon writes the
    // pubkey world-readable (0644) so this unprivileged check can compare bytes.
    static func needsEnroll() -> Bool {
        guard let installed = FileManager.default.contents(atPath: Helper.pubkeyPath),
              let current = SigningKey.existingPublicKeyData() else {
            return true
        }
        return installed != current
    }

    // Retries briefly so a connection attempt rides out the short window where the
    // daemon is rebinding its socket (e.g. just after a reinstall/restart).
    private static func connect(retries: Int = 0) -> Int32? {
        for attempt in 0...retries {
            if let fd = connectOnce() { return fd }
            if attempt < retries { usleep(150_000) }
        }
        return nil
    }

    private static func connectOnce() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { return nil }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(Helper.socketPath.utf8)
        withUnsafeMutablePointer(to: &addr.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: bytes.count + 1) { dst in
                for (i, b) in bytes.enumerated() { dst[i] = CChar(bitPattern: b) }
                dst[bytes.count] = 0
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, size) }
        }
        if r != 0 { close(fd); return nil }
        return fd
    }

    // Ensure the daemon is running and trusts our current signing key. Registers the
    // bundled LaunchDaemon via SMAppService if needed (throwing a user-actionable
    // message + deep-linking to Login Items when approval is pending), waits for the
    // socket, then enrolls/rotates the public key over the socket. No admin password.
    static func prepare(resetSigningKey: Bool = false) throws {
        do {
            try ServiceManager.registerIfNeeded()
        } catch {
            throw HostsError.failed("Couldn't set up the Hosts helper. Quit and reopen Hosts, then try again.")
        }
        try ensureEnabled()

        // Wait for the freshly-launched daemon to bind its socket.
        if !waitForSocket() {
            // The system reports the daemon `.enabled` but its socket never came up.
            // That's the signature of a stale Background Task Management record after
            // an in-place app update (launchd rejects the new binary's code hash with
            // EX_CONFIG and never spawns it), which registerIfNeeded() won't fix
            // because it short-circuits on the `.enabled` status. Re-register once to
            // record the current hash, re-check approval, then wait again.
            do {
                try ServiceManager.reregister()
            } catch {
                throw HostsError.failed("Couldn't restart the Hosts helper. Remove “Hosts” from System Settings → Login Items, reopen Hosts, then unlock again.")
            }
            try ensureEnabled()
            guard waitForSocket() else {
                throw HostsError.failed("The Hosts helper didn't start. Remove “Hosts” from System Settings → Login Items, reopen Hosts, then unlock again.")
            }
        }
        if resetSigningKey || needsEnroll() { try enroll(resetSigningKey: resetSigningKey) }
    }

    // Throw an actionable error unless the service is `.enabled`. Deep-links to Login
    // Items when approval is still pending (e.g. right after a first/re-registration).
    private static func ensureEnabled() throws {
        if ServiceManager.status == .requiresApproval {
            ServiceManager.openLoginItems()
            throw HostsError.failed("Enable “Hosts” in System Settings → Login Items, then unlock again.")
        }
        guard ServiceManager.status == .enabled else {
            throw HostsError.failed("The Hosts helper isn't enabled yet. Enable “Hosts” in System Settings → Login Items, then unlock again.")
        }
    }

    // Poll for the daemon's socket for ~5s. Returns true as soon as it answers.
    private static func waitForSocket() -> Bool {
        for _ in 0..<25 { if isResponding() { return true }; usleep(200_000) }
        return isResponding()
    }

    // Hand the daemon our public key (trust-on-first-use, or a rotation that the
    // daemon only honors for the already-authorized user). Replaces the old root
    // install script's job of planting the pubkey.
    static func enroll(resetSigningKey: Bool = false) throws {
        let pub = try SigningKey.publicKeyData(resetExistingKey: resetSigningKey)
        let request: [String: Any] = ["cmd": "enroll", "protocol": Helper.protocolVersion,
                                      "pubkey": pub.base64EncodedString()]
        try send(request, failureMessage: "Couldn't finish enabling Hosts. Lock Hosts, then unlock again.")
    }

    // Sends a session-signed write request to the daemon. Touch ID unlocks the
    // app session; the helper validates this app's enrolled public key.
    static func write(content: String) throws {
        let ts = Int(Date().timeIntervalSince1970)
        let nonce = UUID().uuidString
        let contentB64 = Data(content.utf8).base64EncodedString()
        let msg = Data("hostshelper-v1\n\(ts)\n\(nonce)\n\(contentB64)".utf8)
        let sig = try SigningKey.sign(msg).base64EncodedString()

        let request: [String: Any] = ["cmd": "write", "protocol": Helper.protocolVersion,
                                      "ts": ts, "nonce": nonce, "content": contentB64, "sig": sig]
        try send(request, failureMessage: "Couldn't save your changes. Try again.")
    }

    // Translate the daemon's machine-readable failure `code` into a user-facing,
    // actionable message. The daemon's raw `error` string is technical (e.g. "bad
    // signature", "stale request") and is never surfaced to the user.
    private static func friendlyError(code: String?, fallback: String) -> String {
        switch code {
        case "not_enrolled", "bad_signature":
            return "Couldn't verify this unlock session. Lock Hosts, then unlock again."
        case "stale_request":
            return "Your Mac's clock looks out of sync, so the change was rejected. Check Date & Time in System Settings, then try again."
        case "replayed_timestamp", "replayed_nonce":
            return "That change was already applied. Try again."
        case "protocol_mismatch":
            return "The Hosts helper needs to finish updating. Quit and reopen Hosts, then try again."
        case "invalid_content":
            return "Those entries can't be saved — remove any unusual characters and try again."
        case "payload_too_large":
            return "This hosts file is too large to save."
        case "write_failed":
            return "Couldn't save changes to /etc/hosts. Try again."
        case "unauthorized":
            return "Hosts can only be unlocked by the macOS user who first set it up."
        default:
            return fallback
        }
    }

    // One JSON object + "\n" per connection, then read the daemon's one-line
    // reply and assert ok. Used by the throwing write/enroll path.
    private static func send(_ request: [String: Any], failureMessage: String) throws {
        guard let obj = try requestObject(request), let ok = obj["ok"] as? Bool else {
            throw HostsError.failed("The Hosts helper isn't responding. Lock Hosts, then unlock again.")
        }
        if !ok {
            throw HostsError.failed(friendlyError(code: obj["code"] as? String, fallback: failureMessage))
        }
    }

    // Socket round-trip returning the parsed reply object (or nil on no/garbled
    // response). Throws only if the request itself can't be serialized or the
    // daemon isn't reachable — callers that just want diagnostics swallow those.
    private static func requestObject(_ request: [String: Any]) throws -> [String: Any]? {
        let body = try JSONSerialization.data(withJSONObject: request)
        guard let fd = connect(retries: 6) else { throw HostsError.failed("The Hosts helper isn't running. Lock Hosts, then unlock again to restart it.") }
        defer { close(fd) }

        var payload = body; payload.append(0x0A)
        _ = payload.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, payload.count) }

        var reply = Data(); var buf = [UInt8](repeating: 0, count: 1024)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            reply.append(contentsOf: buf[0..<n])
            if reply.last == 0x0A { break }
            // The daemon's replies are tiny one-line JSON objects; cap the read so a
            // wedged or misbehaving peer can't stream unbounded data into us.
            if reply.count > 1_000_000 { break }
        }
        return try? JSONSerialization.jsonObject(with: reply) as? [String: Any]
    }

    // MARK: - Diagnostics

    // Snapshot of the daemon's self-reported state (the read-only `status` command).
    struct HelperStatus {
        let version: String
        let protocolVersion: Int
        let enrolled: Bool
        let authUID: UInt32?
        let pubkeyFingerprint: String?
        let lastTs: Int
    }

    // Query the daemon's read-only status. Returns nil if it isn't reachable or
    // the reply can't be parsed. Never throws — diagnostics are best-effort.
    static func status() -> HelperStatus? {
        guard let obj = (try? requestObject(["cmd": "status"])) ?? nil,
              (obj["ok"] as? Bool) == true,
              let version = obj["version"] as? String,
              let proto = obj["protocol"] as? Int else { return nil }
        let uid = (obj["authUID"] as? Int).map { UInt32(truncatingIfNeeded: $0) }
        return HelperStatus(
            version: version,
            protocolVersion: proto,
            enrolled: (obj["enrolled"] as? Bool) ?? false,
            authUID: uid,
            pubkeyFingerprint: obj["pubkeyFingerprint"] as? String,
            lastTs: (obj["lastTs"] as? Int) ?? 0)
    }

    // Single password prompt for the rare privileged shell op that remains (DNS flush).
    static func runAdmin(_ shell: String, prompt: String) throws {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escaped)\" with administrator privileges with prompt \"\(prompt)\""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", appleScript]
        let errPipe = Pipe(); p.standardError = errPipe; p.standardOutput = Pipe()
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if msg.contains("-128") || msg.lowercased().contains("cancel") { throw HostsError.cancelled }
            throw HostsError.failed("Couldn't flush the DNS cache. Try again.")
        }
    }
}
