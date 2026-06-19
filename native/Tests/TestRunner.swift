// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Foundation

// A tiny zero-dependency assertion harness. We don't use XCTest because the app
// is compiled directly with swiftc (no SwiftPM/Xcode), so there's no test bundle
// host. The runner tracks failures and exits non-zero if any assertion fails.
final class TestRunner {
    private(set) var passed = 0
    private(set) var failed = 0
    private var currentGroup = ""

    func group(_ name: String) {
        currentGroup = name
        print("\n=== \(name) ===")
    }

    @discardableResult
    func expect(_ condition: Bool, _ message: String) -> Bool {
        if condition {
            passed += 1
            print("  PASS: \(message)")
        } else {
            failed += 1
            print("  FAIL: \(message)")
        }
        return condition
    }

    func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual == expected {
            passed += 1
            print("  PASS: \(message)")
        } else {
            failed += 1
            print("  FAIL: \(message)  (got \(actual), expected \(expected))")
        }
    }

    func summary() -> Never {
        let total = passed + failed
        print("\n----------------------------------------")
        print("Total: \(total)   Passed: \(passed)   Failed: \(failed)")
        print(failed == 0 ? "ALL TESTS PASSED" : "TESTS FAILED")
        exit(failed == 0 ? 0 : 1)
    }
}
