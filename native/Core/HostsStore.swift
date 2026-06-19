import Darwin
import Foundation
import SwiftUI

// MARK: - Store

// How the Locked pill behaves when clicked: ask each time, or jump straight to a
// preferred method. Persisted in UserDefaults.
enum UnlockMethod: String, CaseIterable {
    case ask, touchID, pin
    var label: String {
        switch self {
        case .ask: return "Ask each time"
        case .touchID: return "Touch ID"
        case .pin: return "PIN"
        }
    }
}

@MainActor
final class HostsStore: ObservableObject {
    static let defaultUnlockKey = "defaultUnlock"

    @Published var lines: [HostLine] = []
    @Published var rawText: String = ""
    @Published var helperReady = false
    @Published var sessionUnlocked = false
    @Published var isPreparing = false
    @Published var pinSet = PinStore.isSet
    @Published var defaultUnlock: UnlockMethod =
        UnlockMethod(rawValue: UserDefaults.standard.string(forKey: HostsStore.defaultUnlockKey) ?? "") ?? .ask {
        didSet { UserDefaults.standard.set(defaultUnlock.rawValue, forKey: HostsStore.defaultUnlockKey) }
    }
    @Published var toast: (msg: String, kind: ToastKind)? = nil
    @Published var selectMode = false
    @Published var selection: Set<UUID> = []
    @Published var collapsed: Set<String> = []
    @Published var statusByIP: [String: HostStatus] = [:]
    @Published var history: [HostSnapshot] = []

    enum ToastKind { case ok, error, info }
    let path = "/etc/hosts"
    var editingReady: Bool { sessionUnlocked && helperReady }

    var entries: [HostEntry] {
        lines.compactMap { if case .entry(let e) = $0 { return e } else { return nil } }
    }
    var activeCount: Int { entries.filter { $0.enabled }.count }
    var blockedCount: Int { entries.filter { ipKind($0.ip) == .block }.count }

    // Entries grouped for display, preserving file order; empty groups dropped.
    func grouped(_ visible: [HostEntry]) -> [(group: HostGroup, entries: [HostEntry])] {
        HostGroup.allCases.compactMap { g in
            let es = visible.filter { group(for: $0) == g }
            return es.isEmpty ? nil : (g, es)
        }
    }

    func status(for e: HostEntry) -> HostStatus {
        switch ipKind(e.ip) {
        case .block, .broadcast: return .na
        default: return statusByIP[e.ip] ?? .na
        }
    }

    func load() {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            showToast("Could not read \(path)", .error); return
        }
        rawText = raw
        lines = parseHosts(raw)
        if history.isEmpty { history = HistoryStore.load() }
        recordSnapshot(raw, label: "Current file")
        helperReady = !HelperClient.needsInstall()
        probeStatus()
    }

    // Prepend a snapshot (newest-first), collapsing no-op writes and capping the
    // log. Persisted immediately so history survives relaunches.
    private func recordSnapshot(_ content: String, label: String) {
        guard content != history.first?.content else { return }
        var updated = history
        updated.insert(HostSnapshot(label: label, content: content), at: 0)
        if updated.count > HistoryStore.maxSnapshots {
            updated = Array(updated.prefix(HistoryStore.maxSnapshots))
        }
        history = updated
        HistoryStore.save(updated)
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

    // Whether biometric Touch ID can be used on this Mac right now.
    var touchIDAvailable: Bool {
        (try? SigningKey.ensureTouchIDAvailable()) != nil
    }

    // Called once on launch: auto-unlock only when the user's default is Touch ID,
    // or when they have no PIN (so Touch ID is the only option — the original
    // behavior). A PIN-preferring user is left locked to choose deliberately.
    func autoUnlockIfPreferred() {
        if defaultUnlock == .touchID || (defaultUnlock != .pin && !pinSet) {
            unlockSession()
        }
    }

    // MARK: PIN unlock (alternative to Touch ID)

    // Saves a new PIN. Returns a user-facing error message, or nil on success.
    func setPIN(_ pin: String) -> String? {
        if let reason = PinStore.validate(pin) { return reason }
        do {
            try PinStore.set(pin)
            pinSet = true
            showToast("PIN saved", .ok)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func removePIN() {
        PinStore.clear()
        pinSet = false
        showToast("PIN removed", .info)
    }

    // Unlocks this session with a PIN instead of Touch ID. Returns false on a
    // wrong PIN so the caller can keep the sheet open. The privileged helper is
    // still installed/validated via the file-based signing key — the same path
    // a Touch ID unlock takes once the session is open.
    @discardableResult
    func unlockWithPIN(_ pin: String) -> Bool {
        guard !isPreparing, PinStore.verify(pin) else { return false }
        sessionUnlocked = true
        isPreparing = true
        Task {
            do {
                if HelperClient.needsInstall() { try HelperClient.install() }
                helperReady = !HelperClient.needsInstall()
                showToast(helperReady ? "Unlocked for this session" : "Finish launch setup before editing",
                          helperReady ? .ok : .error)
            } catch HostsError.cancelled {
            } catch { showToast(error.localizedDescription, .error) }
            isPreparing = false
        }
        return true
    }

    private func indexOfEntry(_ id: UUID) -> Int? {
        lines.firstIndex { if case .entry(let e) = $0 { return e.id == id } else { return false } }
    }

    private func commit(_ mutate: () -> Void, successMessage: String) {
        guard editingReady else {
            showToast("Unlock to make changes.", .error)
            return
        }
        let snapshot = lines
        mutate()
        let pendingContent = serializeHosts(lines)
        Task {
            do {
                try HelperClient.write(content: pendingContent)
                // Keep the optimistic in-memory lines (stable identities) and just
                // resync the raw text. Re-parsing here would mint new UUIDs for
                // every entry, making SwiftUI replace all rows — the visible "jump".
                rawText = pendingContent
                recordSnapshot(pendingContent, label: successMessage)
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
        // `e.enabled` here is the pre-toggle value, so the message describes the
        // resulting state. Editing drops `raw` so this one line re-serializes
        // canonically while every other line in the file passes through verbatim.
        commit({ e.enabled.toggle(); e.raw = nil; lines[i] = .entry(e) },
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

    // MARK: Bulk + group operations (one write per action)

    func setEnabled(_ ids: Set<UUID>, enabled: Bool) {
        guard !ids.isEmpty else { return }
        commit({
            for i in lines.indices {
                if case .entry(var e) = lines[i], ids.contains(e.id) { e.enabled = enabled; e.raw = nil; lines[i] = .entry(e) }
            }
        }, successMessage: "\(ids.count) \(ids.count == 1 ? "entry" : "entries") \(enabled ? "enabled" : "disabled")")
    }

    func deleteMany(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let n = ids.count
        commit({
            lines.removeAll { if case .entry(let e) = $0 { return ids.contains(e.id) } else { return false } }
        }, successMessage: "\(n) \(n == 1 ? "entry" : "entries") deleted")
        selection.removeAll()
    }

    func toggleGroup(_ entries: [HostEntry], on: Bool) {
        setEnabled(Set(entries.map(\.id)), enabled: on)
    }

    // MARK: Selection

    func toggleSelect(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
    func enterSelect() { selectMode = true }
    func exitSelect() { selectMode = false; selection.removeAll() }

    func lock() { sessionUnlocked = false; showToast("Locked", .info) }
    func nudgeLocked() { showToast("Unlock to make changes.", .error) }
    func toggleCollapse(_ g: HostGroup) {
        if collapsed.contains(g.rawValue) { collapsed.remove(g.rawValue) } else { collapsed.insert(g.rawValue) }
    }

    // MARK: Status probe (best-effort reachability; falls back to n/a)

    private var isProbing = false

    func probeStatus() {
        guard !isProbing else { return }   // don't stack overlapping ping storms
        let targets = Array(Set(entries.filter { e in
            e.enabled && ![.block, .broadcast].contains(ipKind(e.ip))
        }.map(\.ip))).prefix(48)
        guard !targets.isEmpty else { return }
        isProbing = true
        Task.detached(priority: .utility) {
            await withTaskGroup(of: (String, HostStatus).self) { grp in
                for ip in targets {
                    grp.addTask { (ip, Self.ping(ip) ? .online : .offline) }
                }
                for await (ip, st) in grp {
                    await MainActor.run { self.statusByIP[ip] = st }
                }
            }
            await MainActor.run { self.isProbing = false }
        }
    }

    nonisolated private static func ping(_ ip: String) -> Bool {
        let tool = ip.contains(":") ? "/sbin/ping6" : "/sbin/ping"
        guard FileManager.default.isExecutableFile(atPath: tool) else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = ip.contains(":") ? ["-c", "1", ip] : ["-c", "1", "-t", "1", ip]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        do { try p.run() } catch { return false }
        // Wait for ping to exit rather than busy-polling; a watchdog terminates it
        // if it ever hangs (e.g. ping6 with no built-in timeout).
        let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.6, execute: watchdog)
        p.waitUntilExit()
        watchdog.cancel()
        return p.terminationStatus == 0
    }

    // Re-derive the in-memory model from freshly written content. Unlike load()
    // this neither re-reads the file nor records another snapshot — the caller has
    // already done both — it just resyncs lines/rawText and clears stale selection.
    private func applyWrittenContent(_ content: String) {
        rawText = content
        lines = parseHosts(content)
        selection.removeAll()
        probeStatus()
    }

    // Restore a past snapshot by writing it back through the helper. The revert
    // itself is recorded as a new snapshot, so it can be undone like any change.
    func revert(to snapshot: HostSnapshot) {
        guard editingReady else {
            showToast("Unlock to make changes.", .error)
            return
        }
        guard snapshot.content != rawText else {
            showToast("Already at this version", .info)
            return
        }
        let previousLines = lines
        let previousRaw = rawText
        Task {
            do {
                try HelperClient.write(content: snapshot.content)
                recordSnapshot(snapshot.content, label: "Reverted to \(Self.shortTime(snapshot.timestamp))")
                applyWrittenContent(snapshot.content)
                showToast("Reverted to earlier version", .ok)
            } catch HostsError.cancelled {
            } catch {
                lines = previousLines
                rawText = previousRaw
                helperReady = !HelperClient.needsInstall()
                showToast(error.localizedDescription, .error)
            }
        }
    }

    static func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: date)
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
