// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Foundation
import Testing

@Suite struct PreferencesTests {
    @Test func autoLockTimeout() {
        let suiteName = "com.etchosts.hostseditor.tests.autolock.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AutoLockPreferences.load(from: defaults) == 30,
                "load: missing preference uses 30-minute default")

        defaults.set(0, forKey: AutoLockPreferences.key)
        #expect(AutoLockPreferences.load(from: defaults) == 0,
                "load: persisted zero preserves Never")

        defaults.set(15, forKey: AutoLockPreferences.key)
        #expect(AutoLockPreferences.load(from: defaults) == 15,
                "load: persisted nonzero timeout is unchanged")
    }
}
