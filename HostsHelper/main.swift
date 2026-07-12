// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

// HostsHelper — a privileged LaunchDaemon (root) that writes /etc/hosts ONLY
// when handed a request whose ECDSA signature verifies against the public key
// registered (as root) at install time. The matching private key is held by the
// app behind a per-session unlock (Touch ID or PIN), so no other app can produce
// a valid request. As defense-in-depth the daemon also rejects socket peers that
// aren't the authorized user (or root).
//
// Wire protocol (one JSON object + "\n" per connection):
//   write  : {"cmd":"write","ts":<int>,"nonce":"<uuid>","content":"<base64>","sig":"<base64>"}
//   enroll : {"cmd":"enroll","pubkey":"<base64>"}
//   reply  : {"ok":true} | {"ok":false,"error":"..."}
// "cmd" is optional and defaults to "write" for backward compatibility.
//
// Signed bytes for a write (must match the app exactly):
//   "hostshelper-v1\n" + ts + "\n" + nonce + "\n" + contentBase64
//
// Trust on first use: with SMAppService there is no longer a root install script
// to plant the trusted public key. Instead the daemon accepts one "enroll" from an
// authorized peer (see peerAuthorized) to record the key root-owned; afterwards it
// only re-enrolls for that same authorized peer (key rotation), so an unrelated
// local user can't swap the trust anchor.

import Foundation
import Security
import CryptoKit
import SystemConfiguration
import Darwin

// Protocol version this daemon speaks. The app (Core/Helper.swift) carries a
// mirrored `Helper.protocolVersion` — the two MUST stay in sync; bump both
// together whenever the wire format changes.
let HELPER_PROTOCOL_VERSION = 1
// Human-readable helper build/version string. Keep matching the app bundle's
// CFBundleShortVersionString.
let HELPER_VERSION = "1.0"

// Security-critical paths are fixed constants — never taken from the environment,
// which the daemon's launching context could otherwise influence to redirect the
// write target or swap the trust anchor.
let HOSTS_PATH  = "/etc/hosts"
let SOCK_PATH   = "/var/run/com.etchosts.hostshelper.sock"
let PUBKEY_PATH = "/Library/Application Support/HostsHelper/pubkey"
let UID_PATH    = "/Library/Application Support/HostsHelper/uid"
let BACKUP_DIR  = "/Library/Application Support/HostsHelper/backups"
// Highest accepted request timestamp, persisted root-owned so replay protection
// survives a daemon restart/reboot (in-memory nonces are lost on restart).
let STATE_PATH  = "/Library/Application Support/HostsHelper/last-ts"

// Largest /etc/hosts we'll accept (decoded). Generous for huge blocklists, but
// bounds memory and rejects absurd payloads.
let MAX_CONTENT_BYTES = 8_000_000

// Largest request we'll read off the socket before giving up. base64 inflates the
// content ~33%, so MAX_CONTENT_BYTES bytes become ~10.7MB on the wire; this cap
// must sit ABOVE that (plus JSON + signature framing) or large-but-legal blocklists
// would be truncated mid-read and misreported as malformed. Headroom over base64.
let MAX_REQUEST_BYTES = 12_000_000

func log(_ s: String) { FileHandle.standardError.write(("[hostshelper] " + s + "\n").data(using: .utf8)!) }

// Stringify a CFError without force-unwrapping: SecKey/SecCode APIs are not
// contractually required to populate the out-error on failure, so a nil error
// must degrade to a label rather than crash the daemon on an error path.
func cfErrorString(_ err: Unmanaged<CFError>?) -> String {
    guard let err else { return "unknown error" }
    return String(describing: err.takeRetainedValue())
}

func loadPublicKey() -> SecKey? {
    guard let raw = FileManager.default.contents(atPath: PUBKEY_PATH) else {
        log("pubkey not found at \(PUBKEY_PATH)"); return nil
    }
    let attrs: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
    ]
    var err: Unmanaged<CFError>?
    guard let key = SecKeyCreateWithData(raw as CFData, attrs as CFDictionary, &err) else {
        log("pubkey import failed: \(cfErrorString(err))"); return nil
    }
    return key
}

func canonicalMessage(ts: Int, nonce: String, contentB64: String) -> Data {
    Data("hostshelper-v1\n\(ts)\n\(nonce)\n\(contentB64)".utf8)
}

// The uid permitted to drive the daemon, recorded at install time. nil if the
// file is missing (e.g. an old install) — in which case peer checking is skipped
// for backward compatibility and the signature remains the sole gate.
func authorizedUID() -> uid_t? {
    guard let s = try? String(contentsOfFile: UID_PATH, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
          let u = UInt32(s) else { return nil }
    return uid_t(u)
}

// Defense-in-depth: only accept connections from the authorized user (or root),
// so a different local user can't even reach the request path. The socket is
// world-connectable for compatibility, so this check does the real gating. The
// caller resolves the peer uid once (fail-closed) and passes it in.
func peerAuthorized(_ peerUID: uid_t, _ authUID: uid_t?) -> Bool {
    // Pre-enrollment (no authUID yet) the connection is allowed through, but the
    // first enroll itself is anchored to the console user in handleEnroll.
    guard let authUID else { return true }
    return peerUID == authUID || peerUID == 0
}

// MARK: - Peer code-signature validation
//
// Beyond getpeereid: require the connecting process to actually be OUR app —
// signed by the same Team as this daemon, carrying the app's bundle identifier,
// and chaining to Apple's root. Without this, any program running as the
// authorized user (e.g. local malware that read the 0600 signing key, or a process
// racing to win first-enrollment) could drive privileged writes. The check closes
// that gap, including for the trust-on-first-use enroll.
//
// The requirement is self-referential — we pin to THIS daemon's own Team
// Identifier rather than a hardcoded team — so it holds for any contributor's
// signing certificate as long as the app and helper are signed together (build.sh
// guarantees that). If our own team can't be determined (e.g. an unsigned/ad-hoc
// dev build, which SMAppService won't register anyway) there is nothing to pin
// against, so we fall back to the uid + signature gates rather than brick the app.
let CLIENT_BUNDLE_ID = "com.etchosts.hostseditor"

// getsockopt level/name for a Unix-socket peer's audit token, from <sys/un.h>.
// Not surfaced by the Swift Darwin overlay, so define the raw values here.
let SOL_LOCAL_LEVEL: Int32 = 0
let LOCAL_PEERTOKEN_OPT: Int32 = 0x006

func peerAuditToken(_ fd: Int32) -> audit_token_t? {
    var token = audit_token_t()
    var len = socklen_t(MemoryLayout<audit_token_t>.size)
    let r = getsockopt(fd, SOL_LOCAL_LEVEL, LOCAL_PEERTOKEN_OPT, &token, &len)
    guard r == 0, len == socklen_t(MemoryLayout<audit_token_t>.size) else { return nil }
    return token
}

func peerSecCode(from token: audit_token_t) -> SecCode? {
    var tok = token
    let tokenData = Data(bytes: &tok, count: MemoryLayout<audit_token_t>.size)
    let attrs = [kSecGuestAttributeAudit: tokenData] as CFDictionary
    var code: SecCode?
    return SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess ? code : nil
}

func teamIdentifier(of code: SecCode) -> String? {
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
          let staticCode else { return nil }
    var info: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let dict = info as? [String: Any] else { return nil }
    return dict[kSecCodeInfoTeamIdentifier as String] as? String
}

// This daemon's own Team Identifier, resolved once at startup. nil for ad-hoc /
// unsigned builds (where there is nothing to pin a peer requirement against).
let ourTeamID: String? = {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
    return teamIdentifier(of: code)
}()

func peerCodeAuthorized(_ fd: Int32, peerUID: uid_t) -> Bool {
    if peerUID == 0 { return true }   // root is already fully privileged; nothing to pin
    guard let team = ourTeamID else {
        log("own team id unavailable (ad-hoc build?); skipping peer code check")
        return true
    }
    guard let token = peerAuditToken(fd), let code = peerSecCode(from: token) else {
        log("could not obtain peer code; rejecting"); return false
    }
    let reqStr = "anchor apple generic and identifier \"\(CLIENT_BUNDLE_ID)\" "
        + "and certificate leaf[subject.OU] = \"\(team)\""
    var req: SecRequirement?
    guard SecRequirementCreateWithString(reqStr as CFString, [], &req) == errSecSuccess, let req else {
        log("could not build code requirement; rejecting"); return false
    }
    let status = SecCodeCheckValidity(code, [], req)
    if status != errSecSuccess { log("peer failed code requirement (status \(status))") }
    return status == errSecSuccess
}

// uid of the user owning the GUI console session (whoever is physically logged in
// at the Mac). Used to anchor first-enrollment trust so an arbitrary local process
// can't race to become the trusted signer before the real app enrolls. nil at the
// login window or when it can't be determined.
func consoleUID() -> uid_t? {
    var uid: uid_t = 0
    var gid: gid_t = 0
    guard let name = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String?,
          !name.isEmpty, name != "loginwindow" else { return nil }
    return uid
}

func loadLastTs() -> Int {
    guard let s = try? String(contentsOfFile: STATE_PATH, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
          let v = Int(s) else { return 0 }
    return v
}

func persistLastTs(_ ts: Int) {
    try? FileManager.default.createDirectory(atPath: (STATE_PATH as NSString).deletingLastPathComponent,
                                             withIntermediateDirectories: true)
    try? String(ts).write(toFile: STATE_PATH, atomically: true, encoding: .utf8)
}

var lastAcceptedTs = loadLastTs()
var recentNonces = Set<String>()
var nonceOrder = [String]()
// Loaded at startup but mutable: enroll can set/rotate the trusted key at runtime
// (no install script plants it anymore). authUID likewise follows the first enroll.
var trustedPubKey: SecKey? = loadPublicKey()
var authUID: uid_t? = authorizedUID()

// Persist the enrolled public key + authorized uid root-owned (dir 0700, files 0644
// so the unprivileged app can read the pubkey back for its readiness check).
func persistEnrollment(pubData: Data, uid: uid_t) -> Bool {
    let dir = (PUBKEY_PATH as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                             attributes: [.posixPermissions: 0o755])
    do {
        try pubData.write(to: URL(fileURLWithPath: PUBKEY_PATH), options: .atomic)
        try String(uid).write(toFile: UID_PATH, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: PUBKEY_PATH)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: UID_PATH)
        return true
    } catch {
        log("enroll persist failed: \(error)"); return false
    }
}

struct WriteError: LocalizedError { let message: String; var errorDescription: String? { message } }

// Reject payloads that aren't a plausible hosts file: too large, or containing
// control characters (NUL etc.) that have no business in /etc/hosts.
func validateContent(_ content: String) -> String? {
    if content.utf8.count > MAX_CONTENT_BYTES { return "content too large" }
    for scalar in content.unicodeScalars where scalar != "\n" && scalar != "\t" && scalar.value < 0x20 {
        return "content has invalid control characters"
    }
    return nil
}

// Keep only the most recent N timestamped backups (filenames sort chronologically).
func pruneBackups(keep: Int = 20) {
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: BACKUP_DIR) else { return }
    let baks = files.filter { $0.hasPrefix("hosts-") && $0.hasSuffix(".bak") }.sorted()
    guard baks.count > keep else { return }
    for f in baks.prefix(baks.count - keep) {
        try? FileManager.default.removeItem(atPath: "\(BACKUP_DIR)/\(f)")
    }
}

func writeHosts(content: String) throws {
    try? FileManager.default.createDirectory(atPath: BACKUP_DIR, withIntermediateDirectories: true,
                                             attributes: [.posixPermissions: 0o700])
    // Back up as raw bytes (not UTF-8 text) so a hand-edited or non-UTF-8 file is
    // preserved verbatim — and fail closed: never overwrite an existing hosts file
    // whose backup couldn't be taken.
    if FileManager.default.fileExists(atPath: HOSTS_PATH) {
        guard let current = try? Data(contentsOf: URL(fileURLWithPath: HOSTS_PATH)) else {
            throw WriteError(message: "could not read existing hosts file for backup")
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        do {
            try current.write(to: URL(fileURLWithPath: "\(BACKUP_DIR)/hosts-\(stamp).bak"), options: .atomic)
        } catch {
            throw WriteError(message: "could not create backup: \(error.localizedDescription)")
        }
        pruneBackups()
    }

    // Symlink-safe atomic replace: write a fresh temp file in the same directory
    // with O_NOFOLLOW|O_EXCL (so an attacker-planted symlink can't redirect the
    // write), then rename() over the target. rename replaces the name itself, so
    // even if /etc/hosts were a symlink it's atomically swapped for a real file.
    let tmpPath = HOSTS_PATH + ".hostsedit.tmp"
    unlink(tmpPath)
    let fd = open(tmpPath, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_EXCL, 0o644)
    if fd < 0 { throw WriteError(message: "open temp failed (errno \(errno))") }
    let bytes = Array(content.utf8)
    let written = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, bytes.count) }
    fchmod(fd, 0o644)
    close(fd)
    guard written == bytes.count else {
        unlink(tmpPath)
        throw WriteError(message: "short write")
    }
    if rename(tmpPath, HOSTS_PATH) != 0 {
        let e = errno
        unlink(tmpPath)
        throw WriteError(message: "rename failed (errno \(e))")
    }
    chown(HOSTS_PATH, 0, 0)   // keep canonical root:wheel ownership
}

// Record (or rotate) the trusted public key.
//   - Re-enroll (key rotation): only the already-authorized uid (or root).
//   - First enroll (authUID still nil): anchored to the console user (or root), so
//     an unrelated local process can't win a race to plant the trust anchor before
//     the real app enrolls.
func handleEnroll(_ obj: [String: Any], peerUID: uid_t) -> String {
    guard let pubB64 = obj["pubkey"] as? String, let pubData = Data(base64Encoded: pubB64) else {
        return errReply("malformed_request", "malformed enroll")
    }
    let attrs: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
    ]
    guard let key = SecKeyCreateWithData(pubData as CFData, attrs as CFDictionary, nil) else {
        return errReply("invalid_content", "invalid public key")
    }

    if let current = authUID {
        // Key rotation: only the authorized user (or root) may replace the anchor.
        guard peerUID == current || peerUID == 0 else {
            return errReply("unauthorized", "enrollment not permitted for this user")
        }
    } else if peerUID != 0 {
        // First enroll from a non-root peer must be the logged-in console user.
        guard let console = consoleUID() else {
            return errReply("unauthorized", "no console user; cannot anchor first enrollment")
        }
        guard peerUID == console else {
            return errReply("unauthorized", "first enrollment must come from the logged-in user")
        }
    }

    guard persistEnrollment(pubData: pubData, uid: peerUID) else {
        return errReply("write_failed", "enroll persist failed")
    }
    trustedPubKey = key
    authUID = peerUID
    log("enrolled key for uid \(peerUID)")
    return "{\"ok\":true}"
}

// Structured failure reply: keeps the legacy `error` string for backward
// compatibility while adding a stable machine-readable `code`. Built via string
// interpolation is risky for arbitrary messages, so escape the message through
// JSONSerialization.
func errReply(_ code: String, _ message: String) -> String {
    let obj: [String: Any] = ["ok": false, "code": code, "error": message]
    if let data = try? JSONSerialization.data(withJSONObject: obj),
       let s = String(data: data, encoding: .utf8) {
        return s
    }
    // Should never happen for these simple values; fall back to a safe literal.
    return "{\"ok\":false,\"code\":\"\(code)\",\"error\":\"helper error\"}"
}

// First 16 hex chars of a SHA-256 over the enrolled pubkey bytes — a stable
// fingerprint that exposes no key material. nil when nothing is enrolled.
func pubkeyFingerprint() -> String? {
    guard let raw = FileManager.default.contents(atPath: PUBKEY_PATH) else { return nil }
    let digest = SHA256.hash(data: raw)
    return digest.map { String(format: "%02x", $0) }.joined().prefix(16).lowercased()
}

// Read-only diagnostics reply. Exposes no secrets (only a fingerprint of the
// pubkey, never the key itself), so any peer already accepted by peerAuthorized
// may call it without a signature.
func handleStatus() -> String {
    let obj: [String: Any] = [
        "ok": true,
        "version": HELPER_VERSION,
        "protocol": HELPER_PROTOCOL_VERSION,
        "enrolled": trustedPubKey != nil,
        "authUID": authUID.map { Int($0) } as Any? ?? NSNull(),
        "pubkeyFingerprint": pubkeyFingerprint() ?? NSNull(),
        "lastTs": lastAcceptedTs,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: obj),
       let s = String(data: data, encoding: .utf8) {
        return s
    }
    return "{\"ok\":true,\"version\":\"\(HELPER_VERSION)\",\"protocol\":\(HELPER_PROTOCOL_VERSION)}"
}

func handle(_ requestData: Data, peerUID: uid_t) -> String {
    guard let obj = try? JSONSerialization.jsonObject(with: requestData) as? [String: Any] else {
        return errReply("malformed_request", "malformed request")
    }
    if (obj["cmd"] as? String) == "enroll" { return handleEnroll(obj, peerUID: peerUID) }
    // Read-only diagnostics — no signature required (exposes no secrets).
    if (obj["cmd"] as? String) == "status" { return handleStatus() }

    // Reject a wire-protocol mismatch loudly rather than silently misparsing a
    // future format. An absent field means a pre-versioned (v1) client, which is
    // still v1-compatible, so only a present-and-different version is rejected.
    if let p = obj["protocol"] as? Int, p != HELPER_PROTOCOL_VERSION {
        return errReply("protocol_mismatch", "unsupported protocol version \(p)")
    }

    // Writes require a trusted key — until enrolled there is nothing to verify against.
    guard let pubKey = trustedPubKey else { return errReply("not_enrolled", "not enrolled") }
    guard let ts = obj["ts"] as? Int,
          let nonce = obj["nonce"] as? String,
          let contentB64 = obj["content"] as? String,
          let sigB64 = obj["sig"] as? String,
          let sig = Data(base64Encoded: sigB64),
          let contentData = Data(base64Encoded: contentB64),
          let content = String(data: contentData, encoding: .utf8)
    else { return errReply("malformed_request", "malformed request") }

    let now = Int(Date().timeIntervalSince1970)
    // Allow only a small clock lead but a wider lag (covers genuine skew without
    // widening the window for a pre-dated, captured request).
    if ts - now > 30 || now - ts > 90 { return errReply("stale_request", "stale request") }
    if ts < lastAcceptedTs - 90 { return errReply("replayed_timestamp", "replayed timestamp") }
    if recentNonces.contains(nonce) { return errReply("replayed_nonce", "replayed nonce") }

    let msg = canonicalMessage(ts: ts, nonce: nonce, contentB64: contentB64)
    var err: Unmanaged<CFError>?
    let ok = SecKeyVerifySignature(pubKey, .ecdsaSignatureMessageX962SHA256, msg as CFData, sig as CFData, &err)
    if !ok { return errReply("bad_signature", "bad signature") }

    if let reason = validateContent(content) { return errReply("invalid_content", reason) }

    do { try writeHosts(content: content) }
    catch { return errReply("write_failed", "write failed: \(error.localizedDescription)") }

    lastAcceptedTs = max(lastAcceptedTs, ts)
    persistLastTs(lastAcceptedTs)
    recentNonces.insert(nonce)
    nonceOrder.append(nonce)
    // Bounded FIFO eviction: drop only the oldest nonce, never the whole set —
    // clearing everything would let an old captured request replay after a flush.
    if nonceOrder.count > 512 {
        let oldest = nonceOrder.removeFirst()
        recentNonces.remove(oldest)
    }
    return "{\"ok\":true}"
}

// Reads one newline-terminated request. `truncated` is true when the peer exceeded
// MAX_REQUEST_BYTES without sending a terminator, so the caller can return a clear
// "too large" error instead of letting a half-read payload masquerade as malformed.
func readRequest(_ fd: Int32) -> (data: Data, truncated: Bool) {
    var buf = [UInt8](repeating: 0, count: 4096)
    var acc = Data()
    while true {
        let n = read(fd, &buf, buf.count)
        if n <= 0 { break }
        acc.append(contentsOf: buf[0..<n])
        if acc.last == 0x0A { break }
        if acc.count > MAX_REQUEST_BYTES { return (acc, true) }
    }
    return (acc, false)
}

func serve() {
    // Writing a reply to a client that already closed its end (e.g. the app's
    // isResponding()/readiness probes connect and close without reading)
    // raises SIGPIPE, whose default action would KILL this daemon. Ignore it so
    // such writes simply fail with EPIPE and the accept loop keeps running.
    signal(SIGPIPE, SIG_IGN)

    // Don't exit when no key is enrolled yet — the daemon must stay up to accept the
    // first "enroll". Writes are rejected ("not enrolled") until a key is recorded.
    if trustedPubKey == nil { log("no enrolled key yet; awaiting enroll") }

    unlink(SOCK_PATH)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    if fd < 0 { log("socket() failed"); exit(1) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(SOCK_PATH.utf8)
    withUnsafeMutablePointer(to: &addr.sun_path) {
        $0.withMemoryRebound(to: CChar.self, capacity: pathBytes.count + 1) { dst in
            for (i, b) in pathBytes.enumerated() { dst[i] = CChar(bitPattern: b) }
            dst[pathBytes.count] = 0
        }
    }
    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    let bindRes = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
    }
    if bindRes != 0 { log("bind() failed errno=\(errno)"); exit(1) }
    chmod(SOCK_PATH, 0o666)
    if listen(fd, 8) != 0 { log("listen() failed"); exit(1) }
    log("listening on \(SOCK_PATH)")

    while true {
        let conn = accept(fd, nil, nil)
        if conn < 0 { continue }
        var on: Int32 = 1
        setsockopt(conn, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        // Fail closed: if we can't identify the peer, drop the connection rather
        // than fall through to an unauthenticated / UID-0 default.
        var pu: uid_t = 0, pg: gid_t = 0
        guard getpeereid(conn, &pu, &pg) == 0 else { close(conn); continue }
        let peerUID = pu
        guard peerAuthorized(peerUID, authUID) else { close(conn); continue }
        // Verify the peer is actually our signed app before reading anything from it.
        guard peerCodeAuthorized(conn, peerUID: peerUID) else {
            log("rejected peer (code signature) uid=\(peerUID)"); close(conn); continue
        }
        let (request, truncated) = readRequest(conn)
        let reply = truncated
            ? errReply("payload_too_large", "request too large")
            : handle(request, peerUID: peerUID)
        _ = (reply + "\n").withCString { write(conn, $0, strlen($0)) }
        close(conn)
    }
}

serve()
