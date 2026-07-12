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
