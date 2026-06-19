// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import SwiftUI

// MARK: - Visual diff

// Renders a line diff (see HostsDiff) with red removals / green additions and a
// +/- gutter, so the user sees exactly what a scheme apply or revert will change
// before it's written. Reusable by the scheme-apply confirm and (later) history.
struct DiffView: View {
    let segments: [DiffSegment]

    // Cap rendered rows so a 100k-line blocklist diff can't stall the UI; the
    // remainder is summarized. Unchanged context is already condensed by collapsing
    // long runs of identical lines.
    private static let maxRows = 1500

    var body: some View {
        let stat = HostsDiff.stat(segments)
        VStack(alignment: .leading, spacing: 0) {
            summaryBar(stat)
            Divider().background(Theme.border)
            if stat.isEmpty {
                Text("No changes — the file is already identical.")
                    .font(.system(size: 12.5)).foregroundColor(Theme.textDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let rows = condensed(segments)
                        ForEach(rows.prefix(Self.maxRows)) { row in
                            DiffRow(segment: row)
                        }
                        if rows.count > Self.maxRows {
                            Text("…and \(rows.count - Self.maxRows) more lines")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Theme.textMut)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .background(Theme.surface2)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func summaryBar(_ stat: DiffStat) -> some View {
        HStack(spacing: 12) {
            Label("\(stat.added) added", systemImage: "plus.circle.fill")
                .foregroundColor(Theme.green)
            Label("\(stat.removed) removed", systemImage: "minus.circle.fill")
                .foregroundColor(Theme.red)
            Spacer()
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.surface)
    }

    // Collapse long runs of unchanged lines to a single "⋯ N unchanged" marker so
    // the changed lines stay readable. Keeps a little context around each change.
    private func condensed(_ segs: [DiffSegment]) -> [DiffSegment] {
        let context = 2
        // Mark which same-lines to keep (those near a change).
        var keep = [Bool](repeating: false, count: segs.count)
        for (i, s) in segs.enumerated() where s.kind != .same {
            for j in max(0, i - context)...min(segs.count - 1, i + context) { keep[j] = true }
        }
        var out: [DiffSegment] = []
        var i = 0
        while i < segs.count {
            if segs[i].kind == .same && !keep[i] {
                var j = i
                while j < segs.count && segs[j].kind == .same && !keep[j] { j += 1 }
                let n = j - i
                out.append(DiffSegment(kind: .same, text: "⋯ \(n) unchanged line\(n == 1 ? "" : "s")",
                                       oldLine: nil, newLine: nil))
                i = j
            } else {
                out.append(segs[i]); i += 1
            }
        }
        return out
    }
}

private struct DiffRow: View {
    let segment: DiffSegment

    var body: some View {
        let (gutter, fg, bg): (String, Color, Color) = {
            switch segment.kind {
            case .added:   return ("+", Theme.green, Theme.green.opacity(0.12))
            case .removed: return ("-", Theme.red, Theme.red.opacity(0.12))
            case .same:    return (" ", Theme.textDim, Color.clear)
            }
        }()
        return HStack(alignment: .top, spacing: 8) {
            Text(gutter)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(fg).frame(width: 12, alignment: .center)
            Text(segment.text.isEmpty ? " " : segment.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(segment.kind == .same ? Theme.text2 : Theme.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10).padding(.vertical, 1.5)
        .background(bg)
    }
}
