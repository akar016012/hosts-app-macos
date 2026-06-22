// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Combine
import Sparkle
import SwiftUI

// MARK: - Sparkle updater

// Owns the Sparkle updater for the app's lifetime. `startingUpdater: true` kicks
// off Sparkle's scheduled background checks (cadence and feed come from the
// Info.plist keys SUEnableAutomaticChecks / SUScheduledCheckInterval / SUFeedURL,
// stamped by build.sh). The bundled appcast is signed with an EdDSA key whose
// public half lives in Info.plist (SUPublicEDKey); the private half stays in the
// release machine's keychain.
//
// `canCheckForUpdates` mirrors the updater's own published flag so the
// "Check for Updates…" menu item disables itself while a check is already in
// flight, matching Sparkle's documented SwiftUI pattern.
final class UpdaterManager: ObservableObject {
    static let shared = UpdaterManager()

    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheckForUpdates = false

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
