import Foundation

// MARK: - Parsing

func looksLikeIP(_ s: String) -> Bool {
    if s.contains(":") {
        // IPv6, optionally with a zone id (e.g. fe80::1%lo0). Require at least two
        // colons so a stray "a:b" doesn't read as an address.
        guard s.range(of: "^[0-9a-fA-F:]+(%[0-9a-zA-Z]+)?$", options: .regularExpression) != nil else { return false }
        return s.filter { $0 == ":" }.count >= 2
    }
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
    for line in raw.components(separatedBy: "\n") {
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
