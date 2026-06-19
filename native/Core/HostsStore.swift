// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

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
                try HelperClient.prepare(resetSigningKey: resetSigningKey)
                helperReady = HelperClient.isReady()
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

    // Called once on launch: auto-unlock only when the user has explicitly chosen
    // Touch ID as their default. Users who never picked a preference (.ask) are left
    // locked to unlock deliberately, rather than being surprised by a biometric
    // prompt thrown at them the instant the app opens.
    func autoUnlockIfPreferred() {
        if defaultUnlock == .touchID { unlockSession() }
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
            sessionUnlocked = true
            isPreparing = true
            Task {
                do {
                    try HelperClient.prepare()
                    helperReady = HelperClient.isReady()
                    showToast(helperReady ? "Unlocked for this session" : "Finish launch setup before editing",
                              helperReady ? .ok : .error)
                } catch HostsError.cancelled {
                } catch { showToast(error.localizedDescription, .error) }
                isPreparing = false
            }
            return .unlocked
        }
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
                showToast(error.localizedDescription, .error)
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
                showToast(error.localizedDescription, .error)
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
            showToast("Export failed: \(error.localizedDescription)", .error)
        }
    }

    // Read a hosts file from disk and replace /etc/hosts with it (privileged).
    func importHosts(from url: URL) {
        guard editingReady else { showToast("Unlock to make changes.", .error); return }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            showToast("Could not read \(url.lastPathComponent)", .error)
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
    // we key by hostname + family. We dedupe per entry (so `127.0.0.1 a a` on a
    // single line isn't a "duplicate") and ignore collisions that exist only
    // among macOS system defaults — a pristine file maps `localhost` to both
    // `::1` and `fe80::1%lo0` (both IPv6) and must not warn — while still
    // flagging the moment a user-defined entry joins the collision. Stat hint.
    var duplicateCount: Int {
        var entryCount: [String: Int] = [:]
        var hasUserEntry: [String: Bool] = [:]
        for e in entries where e.enabled {
            let family = e.ip.contains(":") ? "v6" : "v4"
            let system = isSystemDefault(e)
            for name in Set(e.hostnames.map { $0.lowercased() }) {
                let key = "\(name)|\(family)"
                entryCount[key, default: 0] += 1
                if !system { hasUserEntry[key] = true }
            }
        }
        return entryCount.filter { $0.value > 1 && hasUserEntry[$0.key] == true }.count
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
                showToast(error.localizedDescription, .error)
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
            showToast("Couldn't register helper: \(error.localizedDescription)", .error)
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
            showToast("Helper is \(ServiceManager.statusDescription()).", .error)
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
            showToast("Couldn't remove helper: \(error.localizedDescription)", .error)
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

    // Public entry point for views (e.g. the Schemes sheet) to surface a toast on
    // the main window through the same throttled path as internal messages.
    func notify(_ msg: String, _ kind: ToastKind) { showToast(msg, kind) }

    private func showToast(_ msg: String, _ kind: ToastKind) {
        withAnimation { toast = (msg, kind) }
        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            withAnimation { if toast?.msg == msg { toast = nil } }
        }
    }
}
