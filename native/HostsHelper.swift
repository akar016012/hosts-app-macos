// HostsHelper — a privileged LaunchDaemon (root) that writes /etc/hosts ONLY
// when handed a request signed by the Secure Enclave key whose public key was
// registered (as root) at install time. Each signature requires a live Touch ID
// approval in the app, so no other process can drive it.
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

let HOSTS_PATH  = ProcessInfo.processInfo.environment["HOSTS_PATH"]      ?? "/etc/hosts"
let SOCK_PATH   = ProcessInfo.processInfo.environment["HELPER_SOCKET"]   ?? "/var/run/com.aditya.hostshelper.sock"
let PUBKEY_PATH = ProcessInfo.processInfo.environment["HELPER_PUBKEY"]   ?? "/Library/Application Support/HostsHelper/pubkey"
let BACKUP_DIR  = ProcessInfo.processInfo.environment["HELPER_BACKUP"]   ?? "/Library/Application Support/HostsHelper/backups"

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

var lastAcceptedTs = 0
var recentNonces = Set<String>()

func writeHosts(content: String) throws {
    try? FileManager.default.createDirectory(atPath: BACKUP_DIR, withIntermediateDirectories: true)
    if let current = try? String(contentsOfFile: HOSTS_PATH, encoding: .utf8) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? current.write(toFile: "\(BACKUP_DIR)/hosts-\(stamp).bak", atomically: true, encoding: .utf8)
    }
    try content.write(toFile: HOSTS_PATH, atomically: true, encoding: .utf8)
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

    do { try writeHosts(content: content) }
    catch { return "{\"ok\":false,\"error\":\"write failed: \(error.localizedDescription)\"}" }

    lastAcceptedTs = max(lastAcceptedTs, ts)
    recentNonces.insert(nonce)
    if recentNonces.count > 512 { recentNonces.removeAll() }
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
    guard let pubKey = loadPublicKey() else { log("no public key; exiting"); exit(1) }

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
        let request = readRequest(conn)
        let reply = handle(request, pubKey: pubKey)
        _ = (reply + "\n").withCString { write(conn, $0, strlen($0)) }
        close(conn)
    }
}

serve()
