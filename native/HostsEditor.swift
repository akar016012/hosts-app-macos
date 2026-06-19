import SwiftUI
import AppKit
import Security
import LocalAuthentication
import Darwin

// MARK: - Helper identifiers (must match HostsHelper / build.sh)

enum Helper {
    static let label = "com.aditya.hostshelper"
    static let toolPath = "/Library/PrivilegedHelperTools/com.aditya.hostshelper"
    static let plistPath = "/Library/LaunchDaemons/com.aditya.hostshelper.plist"
    static let pubkeyPath = "/Library/Application Support/HostsHelper/pubkey"
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

// MARK: - Colors

extension Color {
    init(hex: String) {
        let s = Scanner(string: hex.replacingOccurrences(of: "#", with: ""))
        var rgb: UInt64 = 0
        s.scanHexInt64(&rgb)
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: 1)
    }
}

enum Theme {
    static let bg = Color(hex: "12152a")
    static let bg2 = Color(hex: "181d36")
    static let panel = Color(hex: "1e2545")
    static let panel2 = Color(hex: "262f57")
    static let border = Color(hex: "313c6e")
    static let text = Color(hex: "eef1fb")
    static let muted = Color(hex: "9aa4c7")
    static let faint = Color(hex: "6b769c")
    static let blue = Color(hex: "4f7cff")
    static let green = Color(hex: "21d07a")
    static let red = Color(hex: "ff4d6a")
    static let amber = Color(hex: "ffb020")
}

// MARK: - Model

struct HostEntry: Identifiable, Equatable {
    let id: UUID
    var enabled: Bool
    var ip: String
    var hostnames: [String]
    var comment: String

    init(id: UUID = UUID(), enabled: Bool, ip: String, hostnames: [String], comment: String) {
        self.id = id; self.enabled = enabled; self.ip = ip
        self.hostnames = hostnames; self.comment = comment
    }
}

enum HostLine: Identifiable {
    case blank(UUID)
    case comment(UUID, String)
    case entry(HostEntry)
    var id: UUID {
        switch self {
        case .blank(let id): return id
        case .comment(let id, _): return id
        case .entry(let e): return e.id
        }
    }
}

enum Filter: String, CaseIterable { case all = "All", active = "Active", disabled = "Disabled" }

enum HostsError: LocalizedError {
    case cancelled
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .cancelled: return "Cancelled."
        case .failed(let m): return m
        }
    }
}

// MARK: - Parsing

func looksLikeIP(_ s: String) -> Bool {
    if s.range(of: "^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", options: .regularExpression) != nil { return true }
    if s.contains(":"), s.range(of: "^[0-9a-fA-F:]+$", options: .regularExpression) != nil { return true }
    return false
}

func parseEntryBody(_ body: String, enabled: Bool) -> HostEntry? {
    var comment = ""
    var main = body
    if let hashIdx = body.firstIndex(of: "#") {
        comment = String(body[body.index(after: hashIdx)...]).trimmingCharacters(in: .whitespaces)
        main = String(body[..<hashIdx])
    }
    let parts = main.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    guard parts.count >= 2, looksLikeIP(parts[0]) else { return nil }
    return HostEntry(enabled: enabled, ip: parts[0], hostnames: Array(parts.dropFirst()), comment: comment)
}

func parseHosts(_ raw: String) -> [HostLine] {
    var result: [HostLine] = []
    for line in raw.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { result.append(.blank(UUID())); continue }
        if trimmed.hasPrefix("#") {
            let body = trimmed.replacingOccurrences(of: "^#+\\s?", with: "", options: .regularExpression)
            if let e = parseEntryBody(body, enabled: false) { result.append(.entry(e)) }
            else { result.append(.comment(UUID(), line)) }
            continue
        }
        if let e = parseEntryBody(trimmed, enabled: true) { result.append(.entry(e)) }
        else { result.append(.comment(UUID(), line)) }
    }
    if case .blank? = result.last { result.removeLast() }
    return result
}

func serializeHosts(_ lines: [HostLine]) -> String {
    var out: [String] = []
    for line in lines {
        switch line {
        case .blank: out.append("")
        case .comment(_, let text): out.append(text)
        case .entry(let e):
            let prefix = e.enabled ? "" : "# "
            var base = "\(prefix)\(e.ip)\t\(e.hostnames.joined(separator: " "))"
            if !e.comment.isEmpty { base += "  # \(e.comment)" }
            out.append(base)
        }
    }
    return out.joined(separator: "\n") + "\n"
}

// MARK: - Session signing key

enum SigningKey {
    // The session signing key is an EC P-256 private key persisted as a 0600 file
    // in the user's Application Support directory — NOT in the keychain. A
    // keychain-stored key gates each use with an ACL bound to the app's code
    // signature; for an ad-hoc-signed app that identity changes on every rebuild,
    // so macOS prompts for the keychain password on every signature. A file-based
    // key has no ACL and never prompts. Editing is gated by the per-session
    // Touch ID unlock and the key file's 0600 owner-only permissions.

    static func existing() -> SecKey? {
        guard let data = FileManager.default.contents(atPath: Helper.privateKeyPath) else { return nil }
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        return SecKeyCreateWithData(data as CFData, attrs as CFDictionary, nil)
    }

    static func deleteExisting() {
        try? FileManager.default.removeItem(atPath: Helper.privateKeyPath)
        // Clean up keys left in the legacy keychain by older builds.
        for tag in [Helper.keyTag] + Helper.legacyKeyTags {
            let q: [String: Any] = [
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: tag,
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecUseDataProtectionKeychain as String: false,
            ]
            SecItemDelete(q as CFDictionary)
        }
    }

    private static func touchIDUnavailableMessage(_ error: Error?) -> String {
        guard let error else { return "Touch ID is not available on this Mac." }
        let nsError = error as NSError
        guard nsError.domain == LAError.errorDomain, let code = LAError.Code(rawValue: nsError.code) else {
            return error.localizedDescription
        }
        switch code {
        case .biometryNotAvailable:
            return "Touch ID is not available on this Mac."
        case .biometryNotEnrolled:
            return "Set up Touch ID in System Settings before enabling Hosts session unlock."
        case .biometryLockout:
            return "Touch ID is locked. Unlock it in System Settings or with your login password, then try again."
        case .passcodeNotSet:
            return "Set a login password before using Touch ID session unlock."
        default:
            return error.localizedDescription
        }
    }

    private static func touchIDError(_ error: Error) -> HostsError {
        let nsError = error as NSError
        if nsError.domain == LAError.errorDomain, let code = LAError.Code(rawValue: nsError.code) {
            switch code {
            case .userCancel, .appCancel, .systemCancel:
                return .cancelled
            case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout, .passcodeNotSet:
                return .failed(touchIDUnavailableMessage(error))
            default:
                break
            }
        }
        return .failed("Touch ID failed: \(error.localizedDescription)")
    }

    static func ensureTouchIDAvailable() throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error),
              context.biometryType == .touchID else {
            throw HostsError.failed(touchIDUnavailableMessage(error))
        }
    }

    static func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedReason = reason
        context.localizedFallbackTitle = ""

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error),
              context.biometryType == .touchID else {
            throw HostsError.failed(touchIDUnavailableMessage(error))
        }

        do {
            try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            throw touchIDError(error)
        }
    }

    @discardableResult
    static func getOrCreate() throws -> SecKey {
        if let k = existing() { return k }
        try ensureTouchIDAvailable()
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var err: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attrs as CFDictionary, &err) else {
            throw HostsError.failed("Signing key creation failed: \(err!.takeRetainedValue())")
        }
        guard let data = SecKeyCopyExternalRepresentation(key, &err) as Data? else {
            throw HostsError.failed("Signing key export failed: \(err!.takeRetainedValue())")
        }
        try persist(data)
        return key
    }

    // Writes the private key bytes to a 0600 file in a 0700 directory.
    private static func persist(_ data: Data) throws {
        let dir = (Helper.privateKeyPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: URL(fileURLWithPath: Helper.privateKeyPath), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: Helper.privateKeyPath)
    }

    static func publicKeyData(resetExistingKey: Bool = false) throws -> Data {
        if resetExistingKey { deleteExisting() }
        let key = try getOrCreate()
        guard let pub = SecKeyCopyPublicKey(key) else { throw HostsError.failed("No public key.") }
        var err: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(pub, &err) as Data? else {
            throw HostsError.failed("Public key export failed: \(err!.takeRetainedValue())")
        }
        return data
    }

    // Read-only: returns the current key's public bytes, or nil if no key exists.
    // Unlike publicKeyData() this never creates a key or prompts for Touch ID, so
    // it is safe to call from readiness checks like HelperClient.needsInstall().
    static func existingPublicKeyData() -> Data? {
        guard let key = existing(),
              let pub = SecKeyCopyPublicKey(key),
              let data = SecKeyCopyExternalRepresentation(pub, nil) as Data? else { return nil }
        return data
    }

    static func sign(_ data: Data) throws -> Data {
        guard let key = existing() else {
            throw HostsError.failed("Signing key missing — run setup again.")
        }
        var err: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, data as CFData, &err) as Data? else {
            let e = err!.takeRetainedValue()
            let code = CFErrorGetCode(e)
            if code == errSecUserCanceled || code == LAError.userCancel.rawValue || code == -2 {
                throw HostsError.cancelled
            }
            throw HostsError.failed("Signing failed: \(e)")
        }
        return sig
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

        let script = """
        mkdir -p /Library/PrivilegedHelperTools '/Library/Application Support/HostsHelper' && \
        cp '\(helperSrc)' '\(Helper.toolPath)' && chown root:wheel '\(Helper.toolPath)' && chmod 755 '\(Helper.toolPath)' && \
        cp '\(stage)/pubkey' '\(Helper.pubkeyPath)' && chown root:wheel '\(Helper.pubkeyPath)' && chmod 644 '\(Helper.pubkeyPath)' && \
        cp '\(stage)/plist' '\(Helper.plistPath)' && chown root:wheel '\(Helper.plistPath)' && chmod 644 '\(Helper.plistPath)' && \
        launchctl bootout system '\(Helper.plistPath)' 2>/dev/null; \
        launchctl bootstrap system '\(Helper.plistPath)'
        """
        try runAdmin(script, prompt: "Hosts needs your password once to install its privileged helper.")

        // Wait briefly for the daemon to bind its socket.
        for _ in 0..<25 { if isResponding() { return }; usleep(200_000) }
    }

    static func uninstall() throws {
        let script = """
        launchctl bootout system '\(Helper.plistPath)' 2>/dev/null; \
        rm -f '\(Helper.plistPath)' '\(Helper.toolPath)' '\(Helper.pubkeyPath)'
        """
        try runAdmin(script, prompt: "Remove the Hosts Touch ID helper?")
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

// MARK: - Store

@MainActor
final class HostsStore: ObservableObject {
    @Published var lines: [HostLine] = []
    @Published var rawText: String = ""
    @Published var helperReady = false
    @Published var sessionUnlocked = false
    @Published var isPreparing = false
    @Published var toast: (msg: String, kind: ToastKind)? = nil

    enum ToastKind { case ok, error, info }
    let path = "/etc/hosts"
    var editingReady: Bool { sessionUnlocked && helperReady }

    var entries: [HostEntry] {
        lines.compactMap { if case .entry(let e) = $0 { return e } else { return nil } }
    }
    var activeCount: Int { entries.filter { $0.enabled }.count }

    func load() {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            showToast("Could not read \(path)", .error); return
        }
        rawText = raw
        lines = parseHosts(raw)
        helperReady = !HelperClient.needsInstall()
    }

    func prepareSession(resetSigningKey: Bool = false) {
        guard !isPreparing else { return }
        isPreparing = true
        Task {
            do {
                try await SigningKey.authenticate(reason: resetSigningKey ? "reset Hosts session access" : "unlock Hosts for this session")
                sessionUnlocked = true
                if resetSigningKey || HelperClient.needsInstall() {
                    try HelperClient.install(resetSigningKey: resetSigningKey)
                }
                helperReady = !HelperClient.needsInstall()
                showToast(helperReady ? "Hosts is ready for this session" : "Finish launch setup before editing", helperReady ? .ok : .error)
            } catch HostsError.cancelled {
            } catch { showToast(error.localizedDescription, .error) }
            isPreparing = false
        }
    }

    func unlockSession() {
        prepareSession()
    }

    func setupTouchID() {
        prepareSession(resetSigningKey: true)
    }

    private func indexOfEntry(_ id: UUID) -> Int? {
        lines.firstIndex { if case .entry(let e) = $0 { return e.id == id } else { return false } }
    }

    private func commit(_ mutate: () -> Void, successMessage: String) {
        guard editingReady else {
            showToast("Finish launch setup before editing.", .error)
            return
        }
        let snapshot = lines
        mutate()
        let pendingContent = serializeHosts(lines)
        Task {
            do {
                try HelperClient.write(content: pendingContent)
                load()
                showToast(successMessage, .ok)
            } catch HostsError.cancelled {
                lines = snapshot
            } catch {
                lines = snapshot
                // Re-derive readiness from the actual helper state: a transient
                // hiccup keeps the session ready, a real loss demotes the UI.
                helperReady = !HelperClient.needsInstall()
                showToast(error.localizedDescription, .error)
            }
        }
    }

    func toggle(_ id: UUID) {
        guard let i = indexOfEntry(id), case .entry(var e) = lines[i] else { return }
        commit({ e.enabled.toggle(); lines[i] = .entry(e) },
               successMessage: e.enabled ? "Entry disabled" : "Entry enabled")
    }
    func delete(_ id: UUID) {
        guard let i = indexOfEntry(id) else { return }
        commit({ lines.remove(at: i) }, successMessage: "Entry deleted")
    }
    func add(ip: String, hostnames: [String], comment: String, enabled: Bool) {
        commit({ lines.append(.entry(HostEntry(enabled: enabled, ip: ip, hostnames: hostnames, comment: comment))) },
               successMessage: "Entry added")
    }
    func update(_ id: UUID, ip: String, hostnames: [String], comment: String, enabled: Bool) {
        guard let i = indexOfEntry(id), case .entry(let old) = lines[i] else { return }
        commit({ lines[i] = .entry(HostEntry(id: old.id, enabled: enabled, ip: ip, hostnames: hostnames, comment: comment)) },
               successMessage: "Entry updated")
    }
    func saveRaw(_ text: String) {
        guard editingReady else {
            showToast("Finish launch setup before editing.", .error)
            return
        }
        let snapshot = lines
        let pendingContent = text.hasSuffix("\n") ? text : text + "\n"
        Task {
            do {
                try HelperClient.write(content: pendingContent)
                load(); showToast("File saved", .ok)
            } catch HostsError.cancelled {
            } catch {
                lines = snapshot
                helperReady = !HelperClient.needsInstall()
                showToast(error.localizedDescription, .error)
            }
        }
    }

    func flushDNS() {
        do {
            try HelperClient.runAdmin("dscacheutil -flushcache; killall -HUP mDNSResponder",
                                      prompt: "Flush the DNS cache?")
            showToast("DNS cache flushed", .ok)
        } catch HostsError.cancelled {
        } catch { showToast(error.localizedDescription, .error) }
    }

    private func showToast(_ msg: String, _ kind: ToastKind) {
        withAnimation { toast = (msg, kind) }
        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            withAnimation { if toast?.msg == msg { toast = nil } }
        }
    }
}

// MARK: - App

@main
struct HostsEditorApp: App {
    var body: some Scene {
        WindowGroup("Hosts") {
            ContentView().frame(minWidth: 640, minHeight: 540)
        }
        .windowResizability(.contentMinSize)
    }
}

// MARK: - Root view

struct ContentView: View {
    @StateObject private var store = HostsStore()
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var editorEntry: HostEntry? = nil
    @State private var showingEditor = false
    @State private var showingRaw = false

    private var visible: [HostEntry] {
        store.entries.filter { e in
            switch filter {
            case .all: break
            case .active: if !e.enabled { return false }
            case .disabled: if e.enabled { return false }
            }
            let q = search.trimmingCharacters(in: .whitespaces).lowercased()
            if q.isEmpty { return true }
            return e.ip.lowercased().contains(q)
                || e.hostnames.joined(separator: " ").lowercased().contains(q)
                || e.comment.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                toolbar
                Divider().background(Theme.border)
                list
            }
            if let toast = store.toast { toastView(toast) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            store.load()
            store.unlockSession()
        }
        .sheet(isPresented: $showingEditor) {
            EntryEditor(entry: editorEntry) { ip, hosts, comment, enabled in
                if let e = editorEntry {
                    store.update(e.id, ip: ip, hostnames: hosts, comment: comment, enabled: enabled)
                } else {
                    store.add(ip: ip, hostnames: hosts, comment: comment, enabled: enabled)
                }
            }
        }
        .sheet(isPresented: $showingRaw) {
            RawEditor(text: store.rawText) { store.saveRaw($0) }
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Text("⌗")
                .font(.system(size: 26, weight: .bold)).foregroundColor(.white)
                .frame(width: 46, height: 46).background(Theme.blue)
                .clipShape(RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text("Hosts").font(.system(size: 22, weight: .bold)).foregroundColor(Theme.text)
                Text(store.path).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.muted)
            }
            Spacer()
            if store.isPreparing {
                Label("Setting up", systemImage: "touchid")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.amber)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(Theme.amber.opacity(0.14))
                    .clipShape(Capsule())
            } else if !store.editingReady {
                Button { store.unlockSession() } label: { Label("Finish Setup", systemImage: "touchid") }
                    .buttonStyle(SoftButton())
            } else {
                Button { store.setupTouchID() } label: {
                    Label("Ready", systemImage: "touchid")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Theme.green)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(Theme.green.opacity(0.14))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Reset Touch ID session unlock")
            }
            Button { store.flushDNS() } label: { Label("Flush DNS", systemImage: "arrow.triangle.2.circlepath") }
                .buttonStyle(SoftButton())
            Button { showingRaw = true } label: { Text("Raw") }.buttonStyle(SoftButton())
                .disabled(!store.editingReady)
            Button { editorEntry = nil; showingEditor = true } label: { Label("New", systemImage: "plus") }
                .buttonStyle(PrimaryButton())
                .disabled(!store.editingReady)
        }
        .padding(20)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(Theme.muted)
                TextField("Search IP, hostname, or comment…", text: $search)
                    .textFieldStyle(.plain).foregroundColor(Theme.text)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Theme.bg2)
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 11))

            Picker("", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).fixedSize()

            Spacer()
            Text("\(store.activeCount) active · \(store.entries.count) total")
                .font(.system(size: 12)).foregroundColor(Theme.faint)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(visible) { entry in
                    EntryRow(entry: entry,
                             isEnabled: store.editingReady,
                             onToggle: { store.toggle(entry.id) },
                             onEdit: { editorEntry = entry; showingEditor = true },
                             onDelete: { confirmDelete(entry) })
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if visible.isEmpty {
                    VStack(spacing: 10) {
                        Text("🗂️").font(.system(size: 40))
                        Text("No matching entries.").foregroundColor(Theme.muted)
                    }.padding(.top, 60)
                }
            }
            .padding(20)
            .animation(.easeInOut(duration: 0.2), value: visible)
        }
    }

    private func confirmDelete(_ entry: HostEntry) {
        let alert = NSAlert()
        alert.messageText = "Delete entry?"
        alert.informativeText = entry.hostnames.joined(separator: " ")
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn { store.delete(entry.id) }
    }

    private func toastView(_ toast: (msg: String, kind: HostsStore.ToastKind)) -> some View {
        let bg: Color = toast.kind == .ok ? Theme.green : toast.kind == .error ? Theme.red : Theme.panel2
        let fg: Color = toast.kind == .ok ? Color(hex: "04220f") : .white
        return Text(toast.msg)
            .font(.system(size: 13, weight: .semibold)).foregroundColor(fg)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(bg).clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Entry row

struct EntryRow: View {
    let entry: HostEntry
    let isEnabled: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            Toggle("", isOn: Binding(get: { entry.enabled }, set: { _ in onToggle() }))
                .labelsHidden().toggleStyle(.switch).tint(Theme.green)
                .disabled(!isEnabled)

            Text(entry.ip)
                .font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(entry.enabled ? Theme.blue : Theme.faint)
                .clipShape(RoundedRectangle(cornerRadius: 8)).frame(minWidth: 112)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.hostnames.joined(separator: " "))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundColor(Theme.text)
                if !entry.comment.isEmpty {
                    Text("# \(entry.comment)").font(.system(size: 12)).foregroundColor(Theme.faint)
                }
            }
            Spacer()
            Button(action: onEdit) { Image(systemName: "pencil") }.buttonStyle(IconButton())
                .disabled(!isEnabled)
            Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(IconButton(danger: true))
                .disabled(!isEnabled)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(hovering ? Theme.panel2 : Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(hovering ? Theme.blue : Theme.border, lineWidth: 1))
        .overlay(alignment: .leading) {
            Rectangle().fill(entry.enabled ? Theme.green : Theme.faint)
                .frame(width: 4).clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .opacity(entry.enabled ? 1 : 0.62)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

// MARK: - Entry editor sheet

struct EntryEditor: View {
    let entry: HostEntry?
    let onSave: (String, [String], String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var ip = ""
    @State private var hosts = ""
    @State private var comment = ""
    @State private var enabled = true
    @State private var error: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(entry == nil ? "New entry" : "Edit entry")
                .font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
            field("IP address", text: $ip, placeholder: "127.0.0.1")
            field("Hostnames (space-separated)", text: $hosts, placeholder: "example.test www.example.test")
            field("Comment (optional)", text: $comment, placeholder: "Local dev override")
            Toggle(isOn: $enabled) { Text("Enabled").foregroundColor(Theme.text) }.tint(Theme.green)
            if let error { Text(error).foregroundColor(Theme.red).font(.system(size: 13)) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButton())
                Button("Save") { save() }.buttonStyle(PrimaryButton())
            }
        }
        .padding(24).frame(width: 460).background(Theme.panel)
        .onAppear {
            if let e = entry {
                ip = e.ip; hosts = e.hostnames.joined(separator: " ")
                comment = e.comment; enabled = e.enabled
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.muted)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain).font(.system(size: 14, design: .monospaced)).foregroundColor(Theme.text)
                .padding(.horizontal, 12).padding(.vertical, 10).background(Theme.bg2)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func save() {
        let trimmedIP = ip.trimmingCharacters(in: .whitespaces)
        let hostList = hosts.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        if !looksLikeIP(trimmedIP) { error = "Enter a valid IPv4/IPv6 address."; return }
        if hostList.isEmpty { error = "Enter at least one hostname."; return }
        onSave(trimmedIP, hostList, comment.trimmingCharacters(in: .whitespaces), enabled)
        dismiss()
    }
}

// MARK: - Raw editor sheet

struct RawEditor: View {
    let text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var content: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Raw /etc/hosts").font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
            Text("A timestamped backup is saved before every write.")
                .font(.system(size: 12)).foregroundColor(Theme.faint)
            TextEditor(text: $content)
                .font(.system(size: 13, design: .monospaced)).foregroundColor(Theme.text)
                .scrollContentBackground(.hidden).padding(10).background(Theme.bg2)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10)).frame(minHeight: 360)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButton())
                Button("Save file") { onSave(content); dismiss() }.buttonStyle(PrimaryButton())
            }
        }
        .padding(24).frame(width: 700, height: 520).background(Theme.panel)
        .onAppear { content = text }
    }
}

// MARK: - Button styles

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Theme.blue.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SoftButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(configuration.isPressed ? Theme.panel2 : Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct IconButton: ButtonStyle {
    var danger = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .foregroundColor(configuration.isPressed ? .white : Theme.muted)
            .frame(width: 34, height: 34)
            .background((danger ? Theme.red : Theme.panel2).opacity(configuration.isPressed ? 1 : 0))
            .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
