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

    static func needsInstall() -> Bool {
        guard isResponding() else { return true }
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

    // One-time install: places the helper + public key + LaunchDaemon as root.
    static func install(resetSigningKey: Bool = false) throws {
        let pub = try SigningKey.publicKeyData(resetExistingKey: resetSigningKey)
        guard let helperSrc = Bundle.main.resourcePath.map({ $0 + "/com.aditya.hostshelper" }),
              FileManager.default.fileExists(atPath: helperSrc) else {
            throw HostsError.failed("Bundled helper not found. Rebuild with build.sh.")
        }
        let stage = NSTemporaryDirectory() + "hostsinstall-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: stage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: stage) }
        try pub.write(to: URL(fileURLWithPath: stage + "/pubkey"))
        try plist().write(toFile: stage + "/plist", atomically: true, encoding: .utf8)
        // Record the uid allowed to drive the daemon (this user). The daemon checks
        // the connecting peer's credentials against it.
        try String(getuid()).write(toFile: stage + "/uid", atomically: true, encoding: .utf8)

        // Every path below is interpolated into a shell command run as root, so it
        // must be POSIX-quoted — `helperSrc`/`stage` derive from the app's on-disk
        // location, which is user-controlled.
        let script = """
        mkdir -p /Library/PrivilegedHelperTools \(shq("/Library/Application Support/HostsHelper")) && \
        cp \(shq(helperSrc)) \(shq(Helper.toolPath)) && chown root:wheel \(shq(Helper.toolPath)) && chmod 755 \(shq(Helper.toolPath)) && \
        cp \(shq(stage + "/pubkey")) \(shq(Helper.pubkeyPath)) && chown root:wheel \(shq(Helper.pubkeyPath)) && chmod 644 \(shq(Helper.pubkeyPath)) && \
        cp \(shq(stage + "/uid")) \(shq(Helper.uidPath)) && chown root:wheel \(shq(Helper.uidPath)) && chmod 644 \(shq(Helper.uidPath)) && \
        cp \(shq(stage + "/plist")) \(shq(Helper.plistPath)) && chown root:wheel \(shq(Helper.plistPath)) && chmod 644 \(shq(Helper.plistPath)) && \
        launchctl bootout system \(shq(Helper.plistPath)) 2>/dev/null; \
        launchctl bootstrap system \(shq(Helper.plistPath))
        """
        try runAdmin(script, prompt: "Hosts needs your password once to install its privileged helper.")

        // Wait briefly for the daemon to bind its socket.
        for _ in 0..<25 { if isResponding() { return }; usleep(200_000) }
    }

    static func uninstall() throws {
        let script = """
        launchctl bootout system \(shq(Helper.plistPath)) 2>/dev/null; \
        rm -f \(shq(Helper.plistPath)) \(shq(Helper.toolPath)) \(shq(Helper.pubkeyPath)) \(shq(Helper.uidPath))
        """
        try runAdmin(script, prompt: "Remove the Hosts Touch ID helper?")
    }

    // Wraps a string as a single POSIX-shell-quoted token: surround with single
    // quotes and replace each embedded single quote with '\'' . Safe to splice
    // into a /bin/sh command line.
    private static func shq(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // Sends a session-signed write request to the daemon. Touch ID unlocks the
    // app session; the helper validates this app's registered public key.
    static func write(content: String) throws {
        let ts = Int(Date().timeIntervalSince1970)
        let nonce = UUID().uuidString
        let contentB64 = Data(content.utf8).base64EncodedString()
        let msg = Data("hostshelper-v1\n\(ts)\n\(nonce)\n\(contentB64)".utf8)
        let sig = try SigningKey.sign(msg).base64EncodedString()

        let request: [String: Any] = ["ts": ts, "nonce": nonce, "content": contentB64, "sig": sig]
        let body = try JSONSerialization.data(withJSONObject: request)
        guard let fd = connect(retries: 6) else { throw HostsError.failed("Helper not running. Re-run setup.") }
        defer { close(fd) }

        var payload = body; payload.append(0x0A)
        _ = payload.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, payload.count) }

        var reply = Data(); var buf = [UInt8](repeating: 0, count: 1024)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            reply.append(contentsOf: buf[0..<n])
            if reply.last == 0x0A { break }
        }
        guard let obj = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
              let ok = obj["ok"] as? Bool else {
            throw HostsError.failed("No response from helper.")
        }
        if !ok { throw HostsError.failed((obj["error"] as? String) ?? "Helper rejected the write.") }
    }

    private static func plist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key><string>\(Helper.label)</string>
          <key>ProgramArguments</key><array><string>\(Helper.toolPath)</string></array>
          <key>RunAtLoad</key><true/>
          <key>KeepAlive</key><true/>
          <key>StandardErrorPath</key><string>/var/log/hostshelper.log</string>
        </dict>
        </plist>
        """
    }

    // Single password prompt for install/uninstall/flush (rare, privileged shell ops).
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
            throw HostsError.failed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
