// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Foundation
import Testing

private func entry(_ ip: String, _ names: [String], enabled: Bool = true) -> HostEntry {
    HostEntry(enabled: enabled, ip: ip, hostnames: names, comment: "")
}

@Suite struct ClassificationTests {
    @Test func ipKinds() {
        #expect(ipKind("0.0.0.0") == .block, "ipKind: 0.0.0.0 -> .block")
        #expect(ipKind("255.255.255.255") == .broadcast, "ipKind: 255.255.255.255 -> .broadcast")
        #expect(ipKind("127.0.0.1") == .loopback, "ipKind: 127.x -> .loopback")
        #expect(ipKind("127.5.5.5") == .loopback, "ipKind: 127.5.5.5 -> .loopback")
        #expect(ipKind("192.168.1.1") == .privateNet, "ipKind: 192.168.x -> .privateNet")
        #expect(ipKind("10.1.2.3") == .privateNet, "ipKind: 10.x -> .privateNet")
        #expect(ipKind("172.16.0.1") == .privateNet, "ipKind: 172.16.x -> .privateNet")
        #expect(ipKind("172.31.255.1") == .privateNet, "ipKind: 172.31.x -> .privateNet")
        #expect(ipKind("172.15.0.1") == .custom, "ipKind: 172.15.x -> .custom (outside private range)")
        #expect(ipKind("172.32.0.1") == .custom, "ipKind: 172.32.x -> .custom (outside private range)")
        #expect(ipKind("8.8.8.8") == .custom, "ipKind: public IP -> .custom")
        #expect(ipKind("2001:db8::1") == .ipv6, "ipKind: IPv6 -> .ipv6")
    }

    @Test func grouping() {
        #expect(group(for: entry("0.0.0.0", ["ads.tracker.com"])) == .blocking, "group: 0.0.0.0 -> .blocking")
        #expect(group(for: entry("255.255.255.255", ["x"])) == .blocking, "group: 255.255.255.255 (non-broadcasthost) -> .blocking")
        #expect(group(for: entry("127.0.0.1", ["devsite.test"])) == .localDev, "group: 127.x dev host -> .localDev")
        #expect(group(for: entry("192.168.1.5", ["nas"])) == .homeNetwork, "group: 192.168.x -> .homeNetwork")
        #expect(group(for: entry("10.0.0.5", ["server"])) == .homeNetwork, "group: 10.x -> .homeNetwork")
        #expect(group(for: entry("172.20.0.1", ["server"])) == .homeNetwork, "group: 172.20.x -> .homeNetwork")
        #expect(group(for: entry("8.8.8.8", ["public.example.com"])) == .remote, "group: custom public IP -> .remote")
        #expect(group(for: entry("2001:db8::1", ["v6host"])) == .remote, "group: IPv6 -> .remote")
    }

    @Test func systemDefaults() {
        #expect(isSystemDefault(entry("127.0.0.1", ["localhost"])), "isSystemDefault: localhost@127.0.0.1")
        #expect(isSystemDefault(entry("::1", ["localhost"])), "isSystemDefault: localhost@::1")
        #expect(isSystemDefault(entry("fe80::1%lo0", ["localhost"])), "isSystemDefault: localhost@fe80::1%lo0")
        #expect(isSystemDefault(entry("255.255.255.255", ["broadcasthost"])), "isSystemDefault: broadcasthost")
        #expect(!isSystemDefault(entry("192.168.1.1", ["localhost"])), "isSystemDefault: localhost@192.168.1.1 is NOT system")
        #expect(!isSystemDefault(entry("8.8.8.8", ["example.com"])), "isSystemDefault: random host is NOT system")
        #expect(group(for: entry("127.0.0.1", ["localhost"])) == .system, "group: localhost@127.0.0.1 -> .system")
        #expect(group(for: entry("255.255.255.255", ["broadcasthost"])) == .system, "group: broadcasthost -> .system")
    }

    // Per-hostname classification, used by duplicate detection.
    @Test func systemDefaultHost() {
        #expect(isSystemDefaultHost("localhost", ip: "::1"), "isSystemDefaultHost: localhost@::1")
        #expect(isSystemDefaultHost("LocalHost", ip: "fe80::1%lo0"), "isSystemDefaultHost: case-insensitive")
        #expect(isSystemDefaultHost("broadcasthost", ip: "255.255.255.255"), "isSystemDefaultHost: broadcasthost")
        #expect(!isSystemDefaultHost("localhost", ip: "10.0.0.1"), "isSystemDefaultHost: localhost@non-default ip is NOT system")
        #expect(!isSystemDefaultHost("broadcasthost", ip: "127.0.0.1"), "isSystemDefaultHost: broadcasthost@wrong ip is NOT system")
        #expect(!isSystemDefaultHost("myhost", ip: "::1"), "isSystemDefaultHost: alias on a system IP is NOT system")
    }
}
