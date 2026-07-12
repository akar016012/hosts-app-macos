// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Foundation

// MARK: - Line diff

// A minimal line-oriented diff used to preview exactly what applying a scheme (or
// reverting a snapshot) will change before any privileged write happens. Pure and
// UI-free so it can be unit tested; the SwiftUI renderer lives in DiffView.swift.

enum DiffKind { case same, added, removed }

struct DiffSegment: Identifiable, Equatable {
    let id = UUID()
    let kind: DiffKind
    let text: String
    // 1-based line number on its own side (old side for .removed/.same, new side
    // for .added). nil only never happens here but kept optional for callers.
    let oldLine: Int?
    let newLine: Int?
}

struct DiffStat: Equatable {
    var added: Int
    var removed: Int
    var isEmpty: Bool { added == 0 && removed == 0 }
}

enum HostsDiff {
    // Above this many lines on either side we skip the O(n·m) LCS and emit a coarse
    // "removed everything, added everything" diff for the changed region. Huge
    // blocklists (100k+ lines) would otherwise allocate gigabytes for the DP table.
    // The DP buffer is a flat [Int32] (~4·n·m bytes), so this budget caps worst-case
    // memory at ~2500²·4 ≈ 25MB for the changed middle after prefix/suffix trimming.
    static let lcsLineBudget = 2500

    static func stat(_ segments: [DiffSegment]) -> DiffStat {
        segments.reduce(into: DiffStat(added: 0, removed: 0)) { acc, seg in
            switch seg.kind {
            case .added: acc.added += 1
            case .removed: acc.removed += 1
            case .same: break
            }
        }
    }

    static func diff(_ old: String, _ new: String) -> [DiffSegment] {
        // Split on "\n"; a trailing newline yields a final empty element which we
        // drop so "a\n" and "a" compare as one line, matching how the file reads.
        diffLines(splitLines(old), splitLines(new))
    }

    private static func splitLines(_ s: String) -> [String] {
        var parts = s.components(separatedBy: "\n")
        if parts.last == "" { parts.removeLast() }
        return parts
    }

    private static func diffLines(_ old: [String], _ new: [String]) -> [DiffSegment] {
        var segs: [DiffSegment] = []
        var oi = 0, ni = 0

        // Trim the common prefix/suffix cheaply so the expensive LCS only runs on the
        // genuinely-changed middle (and so an unchanged giant blocklist costs O(n)).
        var prefix = 0
        while prefix < old.count && prefix < new.count && old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < (old.count - prefix) && suffix < (new.count - prefix)
            && old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }

        for i in 0..<prefix {
            segs.append(DiffSegment(kind: .same, text: old[i], oldLine: i + 1, newLine: i + 1))
        }
        oi = prefix; ni = prefix

        let oldMid = Array(old[prefix..<(old.count - suffix)])
        let newMid = Array(new[prefix..<(new.count - suffix)])

        if oldMid.count * newMid.count > lcsLineBudget * lcsLineBudget {
            // Coarse fallback: too large to align line-by-line affordably.
            for (k, line) in oldMid.enumerated() {
                segs.append(DiffSegment(kind: .removed, text: line, oldLine: oi + k + 1, newLine: nil))
            }
            for (k, line) in newMid.enumerated() {
                segs.append(DiffSegment(kind: .added, text: line, oldLine: nil, newLine: ni + k + 1))
            }
        } else {
            segs.append(contentsOf: lcsDiff(oldMid, newMid, oldBase: oi, newBase: ni))
        }

        oi = old.count - suffix; ni = new.count - suffix
        for k in 0..<suffix {
            segs.append(DiffSegment(kind: .same, text: old[oi + k], oldLine: oi + k + 1, newLine: ni + k + 1))
        }
        return segs
    }

    // Classic LCS backtrack over the changed middle. `oldBase`/`newBase` offset the
    // reported line numbers so they reflect position in the full file.
    private static func lcsDiff(_ a: [String], _ b: [String], oldBase: Int, newBase: Int) -> [DiffSegment] {
        let n = a.count, m = b.count
        if n == 0 && m == 0 { return [] }
        // Flat (n+1)×(m+1) Int32 DP buffer: dp[i*cols + j] = LCS length of a[i...]
        // and b[j...]. A flat Int32 array uses ~4·n·m bytes with no per-row heap
        // overhead — roughly a quarter of the old nested [[Int]] table.
        let cols = m + 1
        var dp = [Int32](repeating: 0, count: (n + 1) * cols)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    dp[i * cols + j] = a[i] == b[j]
                        ? dp[(i + 1) * cols + (j + 1)] + 1
                        : max(dp[(i + 1) * cols + j], dp[i * cols + (j + 1)])
                }
            }
        }
        var segs: [DiffSegment] = []
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] {
                segs.append(DiffSegment(kind: .same, text: a[i], oldLine: oldBase + i + 1, newLine: newBase + j + 1))
                i += 1; j += 1
            } else if dp[(i + 1) * cols + j] >= dp[i * cols + (j + 1)] {
                segs.append(DiffSegment(kind: .removed, text: a[i], oldLine: oldBase + i + 1, newLine: nil))
                i += 1
            } else {
                segs.append(DiffSegment(kind: .added, text: b[j], oldLine: nil, newLine: newBase + j + 1))
                j += 1
            }
        }
        while i < n { segs.append(DiffSegment(kind: .removed, text: a[i], oldLine: oldBase + i + 1, newLine: nil)); i += 1 }
        while j < m { segs.append(DiffSegment(kind: .added, text: b[j], oldLine: nil, newLine: newBase + j + 1)); j += 1 }
        return segs
    }
}
