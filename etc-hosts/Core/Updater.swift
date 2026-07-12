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
//
// `updateAvailable` / `latestVersion` are driven by a silent appcast probe
// (`checkForUpdateInformation()`), letting the UI show an at-a-glance pill when
// a newer version exists — without popping Sparkle's update sheet.

// Forwards Sparkle's silent-probe results out as a callback. This can't be the
// manager itself: the controller is a stored property that must be initialized
// before `self` is available, so the delegate has to be a separate object.
private final class UpdateProbeDelegate: NSObject, SPUUpdaterDelegate {
    var onResult: ((SUAppcastItem?) -> Void)?
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { onResult?(item) }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) { onResult?(nil) }
}

final class UpdaterManager: ObservableObject {
    static let shared = UpdaterManager()

    private let controller: SPUStandardUpdaterController
    private let probe = UpdateProbeDelegate()
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var updateAvailable = false
    @Published private(set) var latestVersion: String?

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: probe, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        // Fires for the silent probe as well as Sparkle's own scheduled/manual
        // checks, so the pill stays in sync (and self-clears once up to date).
        probe.onResult = { [weak self] item in
            DispatchQueue.main.async {
                self?.updateAvailable = (item != nil)
                self?.latestVersion = item?.displayVersionString
            }
        }
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    // Silent appcast probe — no UI; just refreshes `updateAvailable`.
    func probeForUpdate() {
        controller.updater.checkForUpdateInformation()
    }
}
