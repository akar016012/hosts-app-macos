// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Foundation
import ServiceManagement

// MARK: - Privileged daemon lifecycle (SMAppService)

// Registers/unregisters the bundled root LaunchDaemon via SMAppService (macOS 13+).
// The daemon's plist lives at Contents/Library/LaunchDaemons/<plistName> with
// BundleProgram pointing at Contents/MacOS/<helper>; SMAppService manages the actual
// install location, so there's no admin-password shell script or /Library copy.
//
// First registration leaves the service in `.requiresApproval` until the user enables
// it in System Settings → Login Items; we deep-link there to make that one tap.
enum ServiceManager {
    static var service: SMAppService { SMAppService.daemon(plistName: Helper.plistName) }

    static var status: SMAppService.Status { service.status }

    static var isEnabled: Bool { status == .enabled }

    // Register if not already known to the system. Idempotent: calling register on an
    // enabled/approval-pending service is avoided so we don't surface spurious errors.
    static func registerIfNeeded() throws {
        switch status {
        case .enabled, .requiresApproval:
            return
        default:
            try service.register()
        }
    }

    static func unregister() throws {
        try service.unregister()
    }

    // Force a fresh registration: tear down the existing record and register again.
    // Recovers the case where the system reports the daemon `.enabled` but launchd
    // refuses to actually spawn it (EX_CONFIG) — typically because an in-place app
    // update (e.g. Sparkle) replaced the bundle, leaving the Background Task
    // Management record pinning the old binary's code hash.
    //
    // unregister() is best-effort (a wedged/partial record may already be gone) AND
    // asynchronous: BTM processes the teardown after the call returns, and crucially
    // the published `status` flips to `.notRegistered` *before* that teardown actually
    // finishes — so the status can't be used to know when it's safe to re-register.
    // A register() issued inside the teardown window fails with EPERM ("Operation not
    // permitted"). So we don't trust the status: we wait a fixed grace before each
    // attempt and retry over a several-second budget until BTM lets the register land.
    // This blocks its calling thread, so callers run it off the main actor.
    static func reregister() throws {
        try? service.unregister()
        var lastError: Error?
        // 12 attempts × 0.5s grace ≈ up to 6s for BTM to flush the teardown. The grace
        // comes *before* each register (including the first), so we never register
        // inside the window that yields EPERM.
        for _ in 0..<12 {
            usleep(500_000)
            do { try service.register(); return }
            catch { lastError = error }
        }
        if let lastError { throw lastError }
    }

    // True only when launchd itself reports it refused to spawn the daemon —
    // "spawn failed" with EX_CONFIG (78), the signature of a Background Task
    // Management record pinning a stale code hash after an in-place app update.
    // A daemon that is merely slow to start (e.g. boot-time contention) does NOT
    // show this state, so this is the gate that keeps the automatic repair from
    // firing on a bare timeout. `launchctl print system/...` is readable without
    // privileges; any failure to run/parse it counts as "no evidence".
    static func launchdReportsSpawnFailure() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["print", "system/\(Helper.label)"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return text.contains("spawn failed") || text.contains("last exit code = 78")
    }

    // MARK: Automatic-repair bookkeeping

    // Re-registration resets the user's Login Items approval, so automatic repairs
    // are rate-limited and recorded: without this, a repair that doesn't fix the
    // underlying problem re-runs on every unlock, tearing down the approval the
    // user just granted — an unrecoverable loop. Persisted so it holds across
    // relaunches, and surfaced in Diagnostics so the loop is visible if it happens.
    private static let lastAutoRepairKey = "helperLastAutoRepair"

    static var lastAutoRepairDate: Date? {
        let t = UserDefaults.standard.double(forKey: lastAutoRepairKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static func recordAutoRepair() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastAutoRepairKey)
    }

    static var canAttemptAutoRepair: Bool {
        guard let last = lastAutoRepairDate else { return true }
        return Date().timeIntervalSince(last) > 30 * 60
    }

    // Open System Settings → Login Items so the user can approve a pending daemon.
    static func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // Human-readable status for diagnostics/toasts.
    static func statusDescription() -> String {
        switch status {
        case .enabled: return "enabled"
        case .requiresApproval: return "requires approval"
        case .notRegistered: return "not registered"
        case .notFound: return "not found"
        @unknown default: return "unknown"
        }
    }
}
