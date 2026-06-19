import Foundation
import SwiftUI

// MARK: - Semantic classification (IP kind, source, group, status)

enum IPKind {
    case loopback, ipv6, broadcast, privateNet, block, custom
    var base: Color {
        switch self {
        case .loopback: return Color(hex: "5b8cff"); case .ipv6: return Color(hex: "a78bfa")
        case .broadcast: return Color(hex: "94a3b8"); case .privateNet: return Color(hex: "34d399")
        case .block: return Color(hex: "f87171"); case .custom: return Color(hex: "818cf8")
        }
    }
    var lightText: Color {
        switch self {
        case .loopback: return Color(hex: "1d4ed8"); case .ipv6: return Color(hex: "6d28d9")
        case .broadcast: return Color(hex: "475569"); case .privateNet: return Color(hex: "0f9d6b")
        case .block: return Color(hex: "dc2626"); case .custom: return Color(hex: "4338ca")
        }
    }
}

func ipKind(_ ip: String) -> IPKind {
    if ip == "0.0.0.0" { return .block }
    if ip == "255.255.255.255" { return .broadcast }
    if ip.contains(":") { return .ipv6 }
    if ip.hasPrefix("127.") { return .loopback }
    if ip.hasPrefix("10.") || ip.hasPrefix("192.168.")
        || ip.range(of: "^172\\.(1[6-9]|2\\d|3[01])\\.", options: .regularExpression) != nil { return .privateNet }
    return .custom
}

enum HostStatus { case online, offline, na }

enum HostGroup: String, CaseIterable, Identifiable {
    case system = "System"
    case localDev = "Local Development"
    case homeNetwork = "Home Network"
    case remote = "Remote & Staging"
    case blocking = "Ad & Tracker Blocking"
    var id: String { rawValue }
    var name: String { rawValue }
    var letter: String {
        switch self {
        case .system: return "#"; case .localDev: return "L"; case .homeNetwork: return "H"
        case .remote: return "S"; case .blocking: return "B"
        }
    }
    var source: String {
        switch self {
        case .system: return "macOS default"; case .blocking: return "blocklist"
        case .remote: return "imported"; default: return "manual"
        }
    }
}

func isSystemDefault(_ e: HostEntry) -> Bool {
    let names = Set(e.hostnames.map { $0.lowercased() })
    if names.contains("broadcasthost") { return true }
    if names.contains("localhost"), ["127.0.0.1", "::1", "fe80::1%lo0"].contains(e.ip) { return true }
    return false
}

func group(for e: HostEntry) -> HostGroup {
    if isSystemDefault(e) { return .system }
    switch ipKind(e.ip) {
    case .block, .broadcast: return .blocking
    case .privateNet: return .homeNetwork
    case .loopback: return .localDev
    case .ipv6, .custom: return .remote
    }
}

func sourceTag(for e: HostEntry) -> String { group(for: e).source.uppercased() }

// MARK: - Model

struct HostEntry: Identifiable, Equatable {
    let id: UUID
    var enabled: Bool
    var ip: String
    var hostnames: [String]
    var comment: String

    init(id: UUID = UUID(), enabled: Bool, ip: String, hostnames: [String], comment: String) {
        self.id = id; self.enabled = enabled; self.ip = ip
        self.hostnames = hostnames; self.comment = comment
    }
}

enum HostLine: Identifiable {
    case blank(UUID)
    case comment(UUID, String)
    case entry(HostEntry)
    var id: UUID {
        switch self {
        case .blank(let id): return id
        case .comment(let id, _): return id
        case .entry(let e): return e.id
        }
    }
}

enum Filter: String, CaseIterable { case all = "All", active = "Active", disabled = "Disabled" }

enum HostsError: LocalizedError {
    case cancelled
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .cancelled: return "Cancelled."
        case .failed(let m): return m
        }
    }
}
