// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Darwin
import Foundation

// MARK: - Parsing

// Validates the address part of an IPv6 string via inet_pton, stripping an optional
// zone id (e.g. the "%lo0" in fe80::1%lo0), which inet_pton itself doesn't accept.
// This is stricter and more correct than a loose regex — it rejects malformed
// pseudo-addresses like ":::" that the old pattern let through.
func isIPv6(_ s: String) -> Bool {
    let addr = s.split(separator: "%", maxSplits: 1).first.map(String.init) ?? s
    var buf = [UInt8](repeating: 0, count: 16)
    return addr.withCString { inet_pton(AF_INET6, $0, &buf) == 1 }
}

func looksLikeIP(_ s: String) -> Bool {
    if s.contains(":") { return isIPv6(s) }
    // IPv4: four dotted octets, each 0–255.
    let octets = s.split(separator: ".", omittingEmptySubsequences: false)
    guard octets.count == 4 else { return false }
    return octets.allSatisfy { o in
        !o.isEmpty && o.count <= 3 && o.allSatisfy(\.isNumber) && (Int(o) ?? 256) <= 255
    }
}

func parseEntryBody(_ body: String, enabled: Bool) -> HostEntry? {
    var comment = ""
    var main = body
    if let hashIdx = body.firstIndex(of: "#") {
        comment = String(body[body.index(after: hashIdx)...]).trimmingCharacters(in: .whitespaces)
        main = String(body[..<hashIdx])
    }
    let parts = main.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    guard parts.count >= 2, looksLikeIP(parts[0]) else { return nil }
    return HostEntry(enabled: enabled, ip: parts[0], hostnames: Array(parts.dropFirst()), comment: comment)
}

func parseHosts(_ raw: String) -> [HostLine] {
    var result: [HostLine] = []
    for rawLine in raw.components(separatedBy: "\n") {
        // Tolerate CRLF files: drop a trailing carriage return so it can't leak
        // into a hostname or the preserved `raw` line. (.whitespaces excludes \r.)
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { result.append(.blank(UUID())); continue }
        if trimmed.hasPrefix("#") {
            let body = trimmed.replacingOccurrences(of: "^#+\\s?", with: "", options: .regularExpression)
            if var e = parseEntryBody(body, enabled: false) { e.raw = line; result.append(.entry(e)) }
            else { result.append(.comment(UUID(), line)) }
            continue
        }
        if var e = parseEntryBody(trimmed, enabled: true) { e.raw = line; result.append(.entry(e)) }
        else { result.append(.comment(UUID(), line)) }
    }
    if case .blank? = result.last { result.removeLast() }
    return result
}

func serializeHosts(_ lines: [HostLine]) -> String {
    var out: [String] = []
    for line in lines {
        switch line {
        case .blank: out.append("")
        case .comment(_, let text): out.append(text)
        case .entry(let e):
            // Untouched entries pass through verbatim; only edited entries (raw ==
            // nil) are re-serialized, so an edit never reflows the rest of the file.
            if let raw = e.raw {
                out.append(raw)
            } else {
                let prefix = e.enabled ? "" : "# "
                var base = "\(prefix)\(e.ip)\t\(e.hostnames.joined(separator: " "))"
                if !e.comment.isEmpty { base += "  # \(e.comment)" }
                out.append(base)
            }
        }
    }
    return out.joined(separator: "\n") + "\n"
}
