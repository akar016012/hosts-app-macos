import Darwin
import Foundation
import SwiftUI

// MARK: - Store

@MainActor
final class HostsStore: ObservableObject {
    @Published var lines: [HostLine] = []
    @Published var rawText: String = ""
    @Published var helperReady = false
    @Published var sessionUnlocked = false
    @Published var isPreparing = false
    @Published var toast: (msg: String, kind: ToastKind)? = nil
    @Published var selectMode = false
    @Published var selection: Set<UUID> = []
    @Published var collapsed: Set<String> = []
    @Published var statusByIP: [String: HostStatus] = [:]

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
        helperReady = !HelperClient.needsInstall()
        probeStatus()
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

    // MARK: Bulk + group operations (one write per action)

    func setEnabled(_ ids: Set<UUID>, enabled: Bool) {
        guard !ids.isEmpty else { return }
        commit({
            for i in lines.indices {
                if case .entry(var e) = lines[i], ids.contains(e.id) { e.enabled = enabled; lines[i] = .entry(e) }
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

    func probeStatus() {
        let targets = Array(Set(entries.filter { e in
            e.enabled && ![.block, .broadcast].contains(ipKind(e.ip))
        }.map(\.ip))).prefix(48)
        guard !targets.isEmpty else { return }
        Task.detached(priority: .utility) {
            await withTaskGroup(of: (String, HostStatus).self) { grp in
                for ip in targets {
                    grp.addTask { (ip, Self.ping(ip) ? .online : .offline) }
                }
                for await (ip, st) in grp {
                    await MainActor.run { self.statusByIP[ip] = st }
                }
            }
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
        let deadline = Date().addingTimeInterval(1.6)
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning { p.terminate(); return false }
        return p.terminationStatus == 0
    }

    func saveRaw(_ text: String) {
        guard editingReady else {
            showToast("Unlock to make changes.", .error)
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
