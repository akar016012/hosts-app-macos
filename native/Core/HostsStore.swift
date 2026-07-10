// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import AppKit
import Darwin
import Foundation
import LocalAuthentication
import OpenDirectory
import SwiftUI

// MARK: - Store

// How the Locked pill behaves when clicked: ask each time, or jump straight to a
// preferred method. Persisted in UserDefaults.
enum UnlockMethod: String, CaseIterable {
    case ask, touchID, pin, password
    var label: String {
        switch self {
        case .ask: return "Ask each time"
        case .touchID: return "Touch ID"
        case .pin: return "PIN"
        case .password: return "macOS Password"
        }
    }
    // Compact variant for tight controls (segmented pickers).
    var shortLabel: String {
        switch self {
        case .ask: return "Ask"
        case .password: return "Password"
        default: return label
        }
    }
}

// Result of a PIN unlock attempt, carrying a user-facing message for the wrong
// and locked-out cases so the sheet can explain what happened.
enum PinOutcome { case unlocked, wrong(String), locked(String) }

@MainActor
final class HostsStore: ObservableObject {
    // Single shared instance so menu commands and the Settings scene act on the
    // same state as the main window.
    static let shared = HostsStore()

    static let defaultUnlockKey = "defaultUnlock"

    @Published var lines: [HostLine] = []
    @Published var rawText: String = ""
    @Published var helperReady = false
    // Whether the SMAppService daemon is registered + approved (enabled). Tracked
    // separately from helperReady (which also requires key enrollment) so onboarding
    // can guide the one-time Login Items approval before any unlock.
    @Published var helperRegistered = ServiceManager.isEnabled
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

    @Published var autoLockMinutes = AutoLockPreferences.load() {
        didSet { UserDefaults.standard.set(autoLockMinutes, forKey: AutoLockPreferences.key) }
    }
    private var lastActivityDate = Date()
    private var inactivityTimer: Timer?
    // Handle for the app-lifetime local event monitor that feeds the auto-lock
    // inactivity clock. Owned by the store (not view @State) so theme-driven view
    // rebuilds can never orphan or duplicate it.
    private var activityMonitor: Any?

    enum ToastKind { case ok, error, info }
    let path = "/etc/hosts"
    var editingReady: Bool { sessionUnlocked && helperReady }

    init() { startInactivityTimer() }

    func resetActivityTimer() { lastActivityDate = Date() }

    // Installs the activity monitor exactly once per app lifetime; safe to call again.
    func installActivityMonitor() {
        guard activityMonitor == nil else { return }
        activityMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
        ) { event in
            HostsStore.shared.resetActivityTimer()
            return event
        }
    }

    private func startInactivityTimer() {
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkInactivity() }
        }
    }

    private func checkInactivity() {
        guard sessionUnlocked, autoLockMinutes > 0 else { return }
        if Date().timeIntervalSince(lastActivityDate) >= Double(autoLockMinutes * 60) {
            sessionUnlocked = false
            selectMode = false
            selection.removeAll()
            let label = autoLockMinutes >= 60 ? "1h" : "\(autoLockMinutes)m"
            showToast("Locked after \(label) of inactivity.", .info)
        }
    }

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
            showToast("Couldn't read \(path). Reopen Hosts and try again.", .error); return
        }
        rawText = raw
        lines = parseHosts(raw)
        if history.isEmpty { history = HistoryStore.load() }
        recordSnapshot(raw, label: "Current file")
        helperReady = HelperClient.isReady()
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

    // Wipe the history log, keeping only a fresh snapshot of the current file so
    // the list has a sensible baseline (and the "CURRENT" marker still resolves).
    func clearHistory() {
        let baseline = HostSnapshot(label: "Current file", content: rawText)
        history = [baseline]
        HistoryStore.save(history)
        showToast("History cleared", .info)
    }

    func prepareSession(resetSigningKey: Bool = false) {
        guard !isPreparing else { return }
        isPreparing = true
        Task {
            do {
                try await SigningKey.authenticate(reason: resetSigningKey ? "reset Hosts session access" : "unlock Hosts for this session")
                sessionUnlocked = true
                // prepare() does blocking socket waits and (on repair) several seconds
                // of BTM retries, so run it off the main actor to keep the UI live.
                helperReady = try await Task.detached(priority: .userInitiated) {
                    try HelperClient.prepare(resetSigningKey: resetSigningKey)
                    return HelperClient.isReady()
                }.value
                showToast(helperReady ? "Hosts is ready for this session" : "Finish launch setup before editing", helperReady ? .ok : .error)
            } catch HostsError.cancelled {
            } catch { showToast(userMessage(error), .error) }
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

    // Auto-unlock only when the user has explicitly chosen Touch ID as their
    // default. Users who never picked a preference (.ask) are left locked to
    // unlock deliberately, rather than being surprised by a biometric prompt
    // thrown at them the instant the app opens. May be re-invoked (e.g. a
    // @Published replay after a view rebuild), so it self-guards: never
    // re-prompt when a session is already live or being prepared.
    func autoUnlockIfPreferred() {
        guard !sessionUnlocked, !isPreparing else { return }
        if defaultUnlock == .touchID { unlockSession() }
    }

    // MARK: PIN unlock (alternative to Touch ID)

    // Saves a new PIN. Returns a user-facing error message, or nil on success.
    // Changing an existing PIN requires an unlocked session; setting the first
    // PIN (or one after a reset) is the bootstrap path and stays open.
    func setPIN(_ pin: String) -> String? {
        guard !pinSet || sessionUnlocked else { return "Unlock to change your PIN." }
        if let reason = PinStore.validate(pin) { return reason }
        do {
            try PinStore.set(pin)
            pinSet = true
            showToast("PIN saved", .ok)
            return nil
        } catch {
            return "Couldn't save your PIN. Try again."
        }
    }

    func removePIN() {
        guard sessionUnlocked else { nudgeLocked(); return }
        PinStore.clear()
        pinSet = false
        showToast("PIN removed", .info)
    }

    // Unlocks this session with a PIN instead of Touch ID. Returns false on a
    // wrong PIN so the caller can keep the sheet open. The privileged helper is
    // still installed/validated via the file-based signing key — the same path
    // a Touch ID unlock takes once the session is open.
    func unlockWithPIN(_ pin: String) -> PinOutcome {
        guard !isPreparing else { return .wrong("Please wait…") }
        switch PinStore.verify(pin) {
        case .lockedOut(let seconds):
            return .locked("Too many attempts. Try again in \(Self.formatDuration(seconds)).")
        case .wrong(let remaining):
            return .wrong(remaining <= 2
                ? "Incorrect PIN — \(remaining) attempt\(remaining == 1 ? "" : "s") left."
                : "Incorrect PIN.")
        case .ok:
            beginUnlockedSession()
            return .unlocked
        }
    }

    // Unlocks this session with the macOS login password — the escape hatch for
    // Macs without Touch ID when the PIN is forgotten or locked out. Returns
    // false on a wrong password so the caller can keep the sheet open.
    func unlockWithLoginPassword(_ password: String) -> Bool {
        guard !isPreparing else { return false }
        guard Self.verifyLoginPassword(password) else { return false }
        beginUnlockedSession()
        return true
    }

    // Shared success path for the PIN and login-password unlocks: opens the
    // session and installs/validates the privileged helper.
    private func beginUnlockedSession() {
        sessionUnlocked = true
        isPreparing = true
        Task {
            do {
                // Off the main actor: prepare() blocks on socket waits and, on
                // repair, several seconds of BTM retries.
                helperReady = try await Task.detached(priority: .userInitiated) {
                    try HelperClient.prepare()
                    return HelperClient.isReady()
                }.value
                showToast(helperReady ? "Unlocked for this session" : "Finish launch setup before editing",
                          helperReady ? .ok : .error)
            } catch HostsError.cancelled {
            } catch { showToast(userMessage(error), .error) }
            isPreparing = false
        }
    }

    // Forgot-PIN escape hatch, Touch ID flavor: prove device ownership via the
    // system authentication panel, then wipe the PIN record and its lockout
    // state. Does NOT unlock the session — the user sets a new PIN afterwards
    // and unlocks normally.
    func resetForgottenPIN() async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Password…"
        var probeError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &probeError) else {
            showToast("Can't authenticate on this Mac right now", .error)
            return false
        }
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                             localizedReason: "reset your Hosts PIN")
        } catch {
            // User cancelled or authentication failed — leave everything as is.
            return false
        }
        completePINReset()
        return true
    }

    // Forgot-PIN escape hatch, password flavor: verifies the macOS login
    // password of the current user directly (the LAContext panel on some macOS
    // versions leads with Touch ID and hides the password fallback, so the UI
    // offers this as an explicit option). Returns false on a wrong password so
    // the caller can re-prompt.
    func resetForgottenPIN(loginPassword: String) -> Bool {
        guard Self.verifyLoginPassword(loginPassword) else { return false }
        completePINReset()
        return true
    }

    private func completePINReset() {
        PinStore.clear()
        pinSet = false
        showToast("PIN reset — set a new PIN", .info)
    }

    private static func verifyLoginPassword(_ password: String) -> Bool {
        guard !password.isEmpty,
              let node = try? ODNode(session: ODSession.default(),
                                     type: ODNodeType(kODNodeTypeAuthentication)),
              let record = try? node.record(withRecordType: kODRecordTypeUsers,
                                            name: NSUserName(), attributes: nil)
        else { return false }
        return (try? record.verifyPassword(password)) != nil
    }

    // "45s" / "2m" / "1m 30s" for lockout messaging.
    static func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60, s = seconds % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }

    private func indexOfEntry(_ id: UUID) -> Int? {
        lines.firstIndex { if case .entry(let e) = $0 { return e.id == id } else { return false } }
    }

    // Monotonic token identifying the most recent write. A failed write only rolls
    // back the UI if it's still the latest one — so a stale failure can't clobber a
    // newer optimistic edit that already succeeded or is in flight.
    private var writeSeq = 0

    private func commit(_ mutate: () -> Void, successMessage: String) {
        guard editingReady else {
            showToast("Unlock to make changes.", .error)
            return
        }
        let snapshot = lines
        mutate()
        let pendingContent = serializeHosts(lines)
        writeSeq += 1
        let gen = writeSeq
        Task {
            do {
                // Serialized + off-main so concurrent edits can't interleave writes.
                try await HelperGateway.shared.write(pendingContent)
                // Keep the optimistic in-memory lines (stable identities) and just
                // resync the raw text. Re-parsing here would mint new UUIDs for
                // every entry, making SwiftUI replace all rows — the visible "jump".
                rawText = pendingContent
                recordSnapshot(pendingContent, label: successMessage)
                showToast(successMessage, .ok)
            } catch HostsError.cancelled {
                if gen == writeSeq { lines = snapshot }
            } catch {
                if gen == writeSeq { lines = snapshot }
                // Re-derive readiness from the actual helper state: a transient
                // hiccup keeps the session ready, a real loss demotes the UI.
                helperReady = HelperClient.isReady()
                showToast(userMessage(error), .error)
            }
        }
    }

    // MARK: Import / export

    // Replace the whole file in one privileged write (used by import, scheme apply,
    // and could back other bulk operations). Re-parses on success so identities
    // resync to disk. `onSuccess` runs only after the write lands (e.g. to flush DNS
    // or stamp the applied scheme).
    func replaceAll(with content: String, label: String, onSuccess: (() -> Void)? = nil) {
        guard editingReady else {
            showToast("Unlock to make changes.", .error)
            return
        }
        // The helper rejects \r as a control character, so CRLF content (e.g. a
        // hosts file or scheme bundle authored on Windows) must be normalized here.
        let content = normalizeLineEndings(content)
        let previousLines = lines
        let previousRaw = rawText
        writeSeq += 1
        let gen = writeSeq
        Task {
            do {
                try await HelperGateway.shared.write(content)
                recordSnapshot(content, label: label)
                applyWrittenContent(content)
                showToast(label, .ok)
                onSuccess?()
            } catch HostsError.cancelled {
                if gen == writeSeq { lines = previousLines; rawText = previousRaw }
            } catch {
                if gen == writeSeq { lines = previousLines; rawText = previousRaw }
                helperReady = HelperClient.isReady()
                showToast(userMessage(error), .error)
            }
        }
    }

    // MARK: Scheme apply

    // Apply a named scheme: write its body over /etc/hosts (backed up + snapshotted
    // like any change, so it's reversible), stamp it as the recently-applied scheme,
    // and optionally flush DNS afterward. Ad-hoc content (no scheme) can pass nil id.
    func applyScheme(id: UUID?, name: String, content: String, flushAfter: Bool) {
        guard editingReady else { showToast("Unlock to make changes.", .error); return }
        guard content != rawText else { showToast("“\(name)” is already active", .info); return }
        replaceAll(with: content, label: "Applied “\(name)”") { [weak self] in
            guard let self else { return }
            if let id { SchemeStore.shared.markApplied(id) }
            if flushAfter { self.flushDNS() }
        }
    }

    // Capture the current /etc/hosts as a new named scheme (no privileged write —
    // schemes live in the app's own storage). Returns the created scheme.
    @discardableResult
    func captureCurrentAsScheme(name: String, note: String = "", tags: [String] = []) -> Scheme {
        let store = SchemeStore.shared
        let scheme = Scheme(name: store.uniqueName(from: name.isEmpty ? "Untitled scheme" : name),
                            note: note, tags: tags, content: rawText)
        store.add(scheme)
        showToast("Saved scheme “\(scheme.name)”", .ok)
        return scheme
    }

    // Write the current file contents to a user-chosen location (unprivileged).
    func exportHosts(to url: URL) {
        do {
            try rawText.write(to: url, atomically: true, encoding: .utf8)
            showToast("Exported to \(url.lastPathComponent)", .ok)
        } catch {
            showToast("Couldn't export the file. Try a different location.", .error)
        }
    }

    // Read a hosts file from disk and replace /etc/hosts with it (privileged).
    func importHosts(from url: URL) {
        guard editingReady else { showToast("Unlock to make changes.", .error); return }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            showToast("Couldn't read “\(url.lastPathComponent)”. Make sure it's a plain text hosts file.", .error)
            return
        }
        replaceAll(with: content, label: "Imported \(url.lastPathComponent)")
    }

    // Revert to the previous distinct snapshot (menu/keyboard "Undo Last Change").
    func undoLast() {
        guard editingReady else { showToast("Unlock to make changes.", .error); return }
        guard history.count > 1 else { showToast("Nothing to undo", .info); return }
        revert(to: history[1])
    }

    // Hostnames that appear in more than one enabled entry within the same
    // address family — a likely mistake (first match wins in /etc/hosts).
    // This covers both a host mapped to conflicting IPs and a host repeated
    // redundantly on the same IP; either way only the first line takes effect.
    // A hostname mapped to both an IPv4 and an IPv6 address (e.g. localhost on
    // 127.0.0.1 and ::1) is the standard dual-stack default, not a duplicate, so
    // we key by hostname + family, and we dedupe per entry (so `127.0.0.1 a a`
    // on a single line isn't a "duplicate").
    //
    // A collision is benign only when the OS supplies one hostname at several
    // *distinct* system-default addresses — a pristine file maps `localhost` to
    // both `::1` (loopback) and `fe80::1%lo0` (link-local), both IPv6. Anything
    // else is real: a repeated IP (two identical `127.0.0.1 localhost` lines) or
    // a user-defined entry joining the collision both still warn. Stat hint.
    var duplicateCount: Int {
        struct Group { var count = 0; var ips: Set<String> = []; var user = false }
        var groups: [String: Group] = [:]
        for e in entries where e.enabled {
            let family = e.ip.contains(":") ? "v6" : "v4"
            for name in Set(e.hostnames.map { $0.lowercased() }) {
                let key = "\(name)|\(family)"
                var g = groups[key] ?? Group()
                g.count += 1
                g.ips.insert(e.ip)
                // Classify per hostname, not per entry, so a user alias riding
                // on a system line (`::1 localhost myhost`) still counts as user.
                if !isSystemDefaultHost(name, ip: e.ip) { g.user = true }
                groups[key] = g
            }
        }
        // Real duplicate when a user entry participates, or an IP repeats within
        // the group (ips.count < count); pure distinct-system collisions are skipped.
        return groups.values.filter { $0.count > 1 && ($0.user || $0.ips.count < $0.count) }.count
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

    func lock() { sessionUnlocked = false; selectMode = false; selection.removeAll(); showToast("Locked", .info) }
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
        writeSeq += 1
        let gen = writeSeq
        Task {
            do {
                try await HelperGateway.shared.write(snapshot.content)
                recordSnapshot(snapshot.content, label: "Reverted to \(Self.shortTime(snapshot.timestamp))")
                applyWrittenContent(snapshot.content)
                showToast("Reverted to earlier version", .ok)
            } catch HostsError.cancelled {
            } catch {
                if gen == writeSeq { lines = previousLines; rawText = previousRaw }
                helperReady = HelperClient.isReady()
                showToast(userMessage(error), .error)
            }
        }
    }

    static func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: date)
    }

    // Onboarding: register the bundled daemon and, if macOS needs approval, open
    // System Settings → Login Items. No Touch ID / key enrollment here — that happens
    // at first unlock. Safe to tap repeatedly; reflects the latest status.
    func registerHelper() {
        do {
            try ServiceManager.registerIfNeeded()
        } catch {
            showToast("Couldn't set up the Hosts helper. Reopen Hosts and try again.", .error)
            return
        }
        switch ServiceManager.status {
        case .enabled:
            helperRegistered = true
            showToast("Privileged helper enabled", .ok)
        case .requiresApproval:
            helperRegistered = false
            ServiceManager.openLoginItems()
            showToast("Enable “Hosts” in System Settings → Login Items", .info)
        default:
            helperRegistered = false
            showToast("Couldn't enable the Hosts helper. Reopen Hosts and try again.", .error)
        }
    }

    // Re-read the live registration status (e.g. when an onboarding step appears, or
    // after the user returns from System Settings).
    func refreshHelperStatus() {
        helperRegistered = ServiceManager.isEnabled
    }

    // Tear down the privileged daemon via SMAppService (no admin password). The user
    // can fully remove it from System Settings → Login Items too.
    func unregisterHelper() {
        do {
            try ServiceManager.unregister()
            helperReady = false
            helperRegistered = false
            showToast("Privileged helper removed", .info)
        } catch {
            showToast("Couldn't remove the Hosts helper. Remove “Hosts” from System Settings → Login Items instead.", .error)
        }
    }

    func flushDNS() {
        do {
            try HelperClient.runAdmin("dscacheutil -flushcache; killall -HUP mDNSResponder",
                                      prompt: "Flush the DNS cache?")
            showToast("DNS cache flushed", .ok)
        } catch HostsError.cancelled {
        } catch { showToast(userMessage(error), .error) }
    }

    // Public entry point for views (e.g. the Schemes sheet) to surface a toast on
    // the main window through the same throttled path as internal messages.
    func notify(_ msg: String, _ kind: ToastKind) { showToast(msg, kind) }

    // User-facing text for a thrown error. Our own failures are HostsError and carry
    // an actionable message; anything else (an unexpected system error) is collapsed
    // to a safe generic line so raw system text never reaches the UI.
    private func userMessage(_ error: Error) -> String {
        (error as? HostsError)?.errorDescription ?? "Something went wrong. Try again."
    }

    private func showToast(_ msg: String, _ kind: ToastKind) {
        withAnimation { toast = (msg, kind) }
        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            withAnimation { if toast?.msg == msg { toast = nil } }
        }
    }
}
