// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Foundation

// UserDefaults returns 0 for a missing integer key, but 0 is also the valid
// "Never" auto-lock setting. Keep the presence check in one testable place so
// a new installation gets the default without overwriting an explicit choice.
enum AutoLockPreferences {
    static let key = "autoLockMinutes"
    static let defaultMinutes = 30

    static func load(from defaults: UserDefaults = .standard) -> Int {
        guard defaults.object(forKey: key) != nil else { return defaultMinutes }
        return defaults.integer(forKey: key)
    }
}
