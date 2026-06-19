// HostsHelper — a privileged LaunchDaemon (root) that writes /etc/hosts ONLY
// when handed a request whose ECDSA signature verifies against the public key
// registered (as root) at install time. The matching private key is held by the
// app behind a per-session unlock (Touch ID or PIN), so no other app can produce
// a valid request. As defense-in-depth the daemon also rejects socket peers that
// aren't the authorized user (or root).
//
// Wire protocol (one JSON object + "\n" per connection):
//   request : {"ts":<int>,"nonce":"<uuid>","content":"<base64>","sig":"<base64>"}
//   reply   : {"ok":true} | {"ok":false,"error":"..."}
//
// Signed bytes (must match the app exactly):
//   "hostshelper-v1\n" + ts + "\n" + nonce + "\n" + contentBase64

import Foundation
import Security
import Darwin

// Security-critical paths are fixed constants — never taken from the environment,
// which the daemon's launching context could otherwise influence to redirect the
// write target or swap the trust anchor.
let HOSTS_PATH  = "/etc/hosts"
let SOCK_PATH   = "/var/run/com.aditya.hostshelper.sock"
let PUBKEY_PATH = "/Library/Application Support/HostsHelper/pubkey"
let UID_PATH    = "/Library/Application Support/HostsHelper/uid"
let BACKUP_DIR  = "/Library/Application Support/HostsHelper/backups"

// Largest /etc/hosts we'll accept (decoded). Generous for huge blocklists, but
// bounds memory and rejects absurd payloads.
let MAX_CONTENT_BYTES = 8_000_000

func log(_ s: String) { FileHandle.standardError.write(("[hostshelper] " + s + "\n").data(using: .utf8)!) }

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
        log("pubkey import failed: \(err!.takeRetainedValue())"); return nil
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
// world-connectable for compatibility, so this check does the real gating.
func peerAuthorized(_ fd: Int32, _ authUID: uid_t?) -> Bool {
    guard let authUID else { return true }
    var uid: uid_t = 0
    var gid: gid_t = 0
    if getpeereid(fd, &uid, &gid) != 0 { return false }
    return uid == authUID || uid == 0
}

var lastAcceptedTs = 0
var recentNonces = Set<String>()
var nonceOrder = [String]()

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
    if let current = try? String(contentsOfFile: HOSTS_PATH, encoding: .utf8) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? current.write(toFile: "\(BACKUP_DIR)/hosts-\(stamp).bak", atomically: true, encoding: .utf8)
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

func handle(_ requestData: Data, pubKey: SecKey) -> String {
    guard let obj = try? JSONSerialization.jsonObject(with: requestData) as? [String: Any],
          let ts = obj["ts"] as? Int,
          let nonce = obj["nonce"] as? String,
          let contentB64 = obj["content"] as? String,
          let sigB64 = obj["sig"] as? String,
          let sig = Data(base64Encoded: sigB64),
          let contentData = Data(base64Encoded: contentB64),
          let content = String(data: contentData, encoding: .utf8)
    else { return "{\"ok\":false,\"error\":\"malformed request\"}" }

    let now = Int(Date().timeIntervalSince1970)
    if abs(now - ts) > 90 { return "{\"ok\":false,\"error\":\"stale request\"}" }
    if ts < lastAcceptedTs - 90 { return "{\"ok\":false,\"error\":\"replayed timestamp\"}" }
    if recentNonces.contains(nonce) { return "{\"ok\":false,\"error\":\"replayed nonce\"}" }

    let msg = canonicalMessage(ts: ts, nonce: nonce, contentB64: contentB64)
    var err: Unmanaged<CFError>?
    let ok = SecKeyVerifySignature(pubKey, .ecdsaSignatureMessageX962SHA256, msg as CFData, sig as CFData, &err)
    if !ok { return "{\"ok\":false,\"error\":\"bad signature\"}" }

    if let reason = validateContent(content) { return "{\"ok\":false,\"error\":\"\(reason)\"}" }

    do { try writeHosts(content: content) }
    catch { return "{\"ok\":false,\"error\":\"write failed: \(error.localizedDescription)\"}" }

    lastAcceptedTs = max(lastAcceptedTs, ts)
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

func readRequest(_ fd: Int32) -> Data {
    var buf = [UInt8](repeating: 0, count: 4096)
    var acc = Data()
    while true {
        let n = read(fd, &buf, buf.count)
        if n <= 0 { break }
        acc.append(contentsOf: buf[0..<n])
        if acc.last == 0x0A { break }
        if acc.count > 5_000_000 { break }
    }
    return acc
}

func serve() {
    // Writing a reply to a client that already closed its end (e.g. the app's
    // isResponding()/needsInstall() probes connect and close without reading)
    // raises SIGPIPE, whose default action would KILL this daemon. Ignore it so
    // such writes simply fail with EPIPE and the accept loop keeps running.
    signal(SIGPIPE, SIG_IGN)

    guard let pubKey = loadPublicKey() else { log("no public key; exiting"); exit(1) }
    let authUID = authorizedUID()

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
        guard peerAuthorized(conn, authUID) else { close(conn); continue }
        let request = readRequest(conn)
        let reply = handle(request, pubKey: pubKey)
        _ = (reply + "\n").withCString { write(conn, $0, strlen($0)) }
        close(conn)
    }
}

serve()
