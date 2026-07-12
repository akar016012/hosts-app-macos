// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Foundation

// Encodes a Swift string as a JSON string literal (with surrounding quotes), used
// to build hand-written legacy JSON for the back-compat decode tests.
func jsonString(_ s: String) -> String {
    let data = try! JSONEncoder().encode(s)
    return String(data: data, encoding: .utf8)!
}

// Safety gate for suites that touch files under NSHomeDirectory() (PinStore,
// HistoryStore). The shared scheme sets CFFIXED_USER_HOME=/tmp/hosts-tests-home —
// the only mechanism NSHomeDirectory() honors, and only when set at process
// spawn. If that didn't take effect, abort loudly rather than clobber the real
// ~/Library/Application Support/HostsEditor (pin.json, history.json).
func requireTemporaryHome() {
    let home = NSHomeDirectory()
    let isTempHome = home.contains("/var/folders/") || home.contains("/tmp/") || home.hasPrefix("/private/")
    precondition(isTempHome, """
        NSHomeDirectory() is \(home) — refusing to run filesystem tests against the \
        real home. Run via the etc-hosts scheme (xcodebuild test / ⌘U), which sets \
        CFFIXED_USER_HOME.
        """)
}
