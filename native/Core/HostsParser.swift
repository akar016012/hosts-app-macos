import Foundation

// MARK: - Parsing

func looksLikeIP(_ s: String) -> Bool {
    if s.range(of: "^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", options: .regularExpression) != nil { return true }
    if s.contains(":"), s.range(of: "^[0-9a-fA-F:]+$", options: .regularExpression) != nil { return true }
    return false
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
            if let e = parseEntryBody(body, enabled: false) { result.append(.entry(e)) }
            else { result.append(.comment(UUID(), line)) }
            continue
        }
        if let e = parseEntryBody(trimmed, enabled: true) { result.append(.entry(e)) }
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
            let prefix = e.enabled ? "" : "# "
            var base = "\(prefix)\(e.ip)\t\(e.hostnames.joined(separator: " "))"
            if !e.comment.isEmpty { base += "  # \(e.comment)" }
            out.append(base)
        }
    }
    return out.joined(separator: "\n") + "\n"
}
