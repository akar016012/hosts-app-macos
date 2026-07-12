// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Foundation
import Testing

@Suite struct DiffTests {
    // Identical content -> no changes, every segment is .same.
    @Test func identicalContent() {
        let segs = HostsDiff.diff("127.0.0.1 a\n10.0.0.1 b\n", "127.0.0.1 a\n10.0.0.1 b\n")
        #expect(HostsDiff.stat(segs).isEmpty, "diff: identical content -> empty stat")
        #expect(segs.allSatisfy { $0.kind == .same }, "diff: identical content -> all .same")
    }

    // Trailing-newline insensitivity: "a\n" vs "a" compare equal (final empty dropped).
    @Test func trailingNewlineIgnored() {
        #expect(HostsDiff.stat(HostsDiff.diff("127.0.0.1 a\n", "127.0.0.1 a")).isEmpty,
                "diff: trailing newline difference is ignored")
    }

    @Test func pureAddition() {
        let segs = HostsDiff.diff("127.0.0.1 a\n", "127.0.0.1 a\n10.0.0.1 b\n")
        let stat = HostsDiff.stat(segs)
        #expect(stat.added == 1, "diff: one appended line -> 1 added")
        #expect(stat.removed == 0, "diff: one appended line -> 0 removed")
        let added = segs.first { $0.kind == .added }
        #expect(added?.text == "10.0.0.1 b", "diff: added segment carries the new line text")
        #expect(added?.newLine == 2, "diff: added segment reports new-side line number")
    }

    @Test func pureRemoval() {
        let segs = HostsDiff.diff("127.0.0.1 a\n10.0.0.1 b\n", "127.0.0.1 a\n")
        let stat = HostsDiff.stat(segs)
        #expect(stat.removed == 1, "diff: one dropped line -> 1 removed")
        #expect(stat.added == 0, "diff: one dropped line -> 0 added")
        #expect(segs.first { $0.kind == .removed }?.oldLine == 2,
                "diff: removed segment reports old-side line number")
    }

    // Change a middle line, common prefix/suffix preserved as context.
    @Test func changedMiddleLine() {
        let old = "127.0.0.1 a\n10.0.0.1 OLD\n192.168.0.1 c\n"
        let new = "127.0.0.1 a\n10.0.0.1 NEW\n192.168.0.1 c\n"
        let segs = HostsDiff.diff(old, new)
        let stat = HostsDiff.stat(segs)
        #expect(stat.added == 1, "diff: changed line -> 1 added")
        #expect(stat.removed == 1, "diff: changed line -> 1 removed")
        #expect(segs.contains { $0.kind == .same && $0.text == "127.0.0.1 a" }, "diff: unchanged prefix kept as .same")
        #expect(segs.contains { $0.kind == .same && $0.text == "192.168.0.1 c" }, "diff: unchanged suffix kept as .same")
    }

    // Empty -> content is all additions; content -> empty is all removals.
    @Test func emptyToContentAndBack() {
        let toFull = HostsDiff.stat(HostsDiff.diff("", "a\nb\nc\n"))
        #expect(toFull.added == 3, "diff: empty -> 3 lines is 3 added")
        #expect(toFull.removed == 0, "diff: empty -> content has no removals")
        let toEmpty = HostsDiff.stat(HostsDiff.diff("a\nb\nc\n", ""))
        #expect(toEmpty.removed == 3, "diff: content -> empty is 3 removed")
    }
}
