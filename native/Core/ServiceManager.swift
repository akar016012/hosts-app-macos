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
