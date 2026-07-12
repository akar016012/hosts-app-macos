// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Foundation
import Testing

@Suite struct LooksLikeIPTests {
    @Test func validIPv4() {
        #expect(looksLikeIP("127.0.0.1"), "valid IPv4 loopback")
        #expect(looksLikeIP("192.168.1.1"), "valid IPv4 private")
        #expect(looksLikeIP("255.255.255.255"), "valid IPv4 broadcast")
        #expect(looksLikeIP("0.0.0.0"), "valid IPv4 all-zeros")
    }

    @Test func invalidIPv4() {
        #expect(!looksLikeIP("256.0.0.1"), "invalid: octet > 255")
        #expect(!looksLikeIP("1.2.3"), "invalid: too few octets")
        #expect(!looksLikeIP("1.2.3.4.5"), "invalid: too many octets")
        #expect(!looksLikeIP("1..3.4"), "invalid: empty octet")
        #expect(!looksLikeIP("1.2.3."), "invalid: trailing empty octet")
        #expect(!looksLikeIP(""), "invalid: empty string")
    }

    @Test func validIPv6() {
        #expect(looksLikeIP("::1"), "valid IPv6 loopback")
        #expect(looksLikeIP("fe80::1"), "valid IPv6 link-local")
        #expect(looksLikeIP("2001:db8::ff00:42:8329"), "valid full IPv6")
        #expect(looksLikeIP("fe80::1%lo0"), "valid IPv6 with zone id")
    }

    @Test func invalidIPv6AndHostnames() {
        #expect(!looksLikeIP("a:b"), "invalid: single-colon a:b is not IPv6")
        #expect(!looksLikeIP("example.com"), "invalid: hostname")
        #expect(!looksLikeIP("localhost"), "invalid: bare hostname")
        // Malformed pseudo-IPv6 is rejected: looksLikeIP validates the address via
        // inet_pton (after stripping any %zone), so ":::" no longer reads as an address.
        #expect(!looksLikeIP(":::"), "invalid: ':::' is not a valid IPv6 address")
        #expect(!looksLikeIP("12345::1"), "invalid: out-of-range IPv6 group")
        #expect(!looksLikeIP("gggg::1"), "invalid: non-hex IPv6 group")
    }
}

@Suite struct ParseSerializeTests {
    @Test func enabledEntry() {
        let lines = parseHosts("127.0.0.1\tlocalhost\n")
        #expect(lines.count == 1, "enabled entry: one line")
        if case .entry(let e) = lines[0] {
            #expect(e.enabled, "enabled entry: enabled flag true")
            #expect(e.ip == "127.0.0.1", "enabled entry: ip parsed")
            #expect(e.hostnames == ["localhost"], "enabled entry: hostnames parsed")
        } else {
            Issue.record("enabled entry: not classified as .entry")
        }
    }

    @Test func disabledEntry() {
        let lines = parseHosts("# 10.0.0.5 myhost\n")
        if case .entry(let e) = lines[0] {
            #expect(!e.enabled, "disabled entry: enabled flag false")
            #expect(e.ip == "10.0.0.5", "disabled entry: ip parsed")
            #expect(e.hostnames == ["myhost"], "disabled entry: hostnames parsed")
        } else {
            Issue.record("disabled entry: not classified as .entry")
        }
    }

    @Test func pureComment() {
        let lines = parseHosts("# This is just a comment\n")
        if case .comment(_, let text) = lines[0] {
            #expect(text == "# This is just a comment", "pure comment: preserved verbatim")
        } else {
            Issue.record("pure comment: not classified as .comment")
        }
    }

    @Test func blankLineInMiddle() {
        let lines = parseHosts("127.0.0.1 a\n\n127.0.0.2 b\n")
        #expect(lines.count == 3, "blank line: preserved between entries")
        if case .blank = lines[1] {} else { Issue.record("blank line: middle is not .blank") }
    }

    @Test func inlineComment() {
        let lines = parseHosts("127.0.0.1 myhost # inline note\n")
        if case .entry(let e) = lines[0] {
            #expect(e.comment == "inline note", "inline comment: captured into comment")
            #expect(e.hostnames == ["myhost"], "inline comment: hostname excludes comment")
        } else {
            Issue.record("inline comment: not classified as .entry")
        }
    }

    @Test func ipv6ZoneEntry() {
        let lines = parseHosts("fe80::1%lo0 localhost\n")
        if case .entry(let e) = lines[0] {
            #expect(e.ip == "fe80::1%lo0", "ipv6 zone: ip with zone parsed")
            #expect(isSystemDefault(e), "ipv6 zone: localhost@fe80::1%lo0 is system default")
        } else {
            Issue.record("ipv6 zone: not classified as .entry")
        }
    }

    // Trailing blank line dropped by parser. A single trailing "\n" splits into an
    // empty final component, which becomes a .blank that the parser removes — so a
    // canonically-newline-terminated file yields only its content lines.
    @Test func trailingBlankDropped() {
        let lines = parseHosts("127.0.0.1 a\n")
        #expect(lines.count == 1, "trailing blank: single trailing newline dropped (only entry remains)")
        if case .entry = lines.last {} else { Issue.record("trailing blank: last line is not the entry") }
    }

    // Document current behavior: the parser strips only ONE trailing blank, so a file
    // ending in TWO newlines keeps one interior blank line.
    @Test func onlyOneTrailingBlankDropped() {
        let lines = parseHosts("127.0.0.1 a\n\n")
        #expect(lines.count == 2, "trailing blank: only one trailing blank dropped (current behavior)")
        if case .blank = lines.last {} else { Issue.record("trailing blank: a second trailing blank should survive") }
    }

    @Test func serializeAppendsTrailingNewline() {
        let out = serializeHosts([.entry(HostEntry(enabled: true, ip: "127.0.0.1", hostnames: ["x"], comment: ""))])
        #expect(out.hasSuffix("\n"), "serialize: appends trailing newline")
    }

    // Round-trip on a realistic /etc/hosts sample (lines already in canonical form).
    // Because untouched entries preserve their `raw`, parse->serialize is byte-for-byte.
    @Test func realisticRoundTrip() {
        let sample = """
        ##
        # Host Database
        #
        # localhost is used to configure the loopback interface
        ##
        127.0.0.1\tlocalhost
        255.255.255.255\tbroadcasthost
        ::1             localhost
        fe80::1%lo0\tlocalhost
        # 0.0.0.0 ads.example.com
        10.0.0.5\tmyhost  # inline note

        192.168.1.42\trouter.local
        """
        // serializeHosts always ends with a newline; ensure the input does too so the
        // comparison is apples-to-apples.
        let input = sample + "\n"
        #expect(serializeHosts(parseHosts(input)) == input,
                "round-trip: realistic sample is byte-for-byte preserved")
    }
}

@Suite struct ValidateHostnameTests {
    @Test func validHostnames() {
        #expect(validateHostname("localhost") == nil, "valid: bare hostname")
        #expect(validateHostname("example.com") == nil, "valid: two labels")
        #expect(validateHostname("www.example-site.co.uk") == nil, "valid: hyphens and multiple labels")
        #expect(validateHostname("my_host.local") == nil, "valid: underscore allowed")
        #expect(validateHostname("a1.b2.c3") == nil, "valid: digits in labels")
        #expect(validateHostname(String(repeating: "a", count: 63) + ".com") == nil, "valid: 63-char label")
    }

    @Test func invalidHostnames() {
        #expect(validateHostname("foo#bar") != nil, "invalid: '#' (the round-trip corruption bug)")
        #expect(validateHostname("foo,bar") != nil, "invalid: comma")
        #expect(validateHostname("foo/bar") != nil, "invalid: slash")
        #expect(validateHostname("héllo.com") != nil, "invalid: non-ASCII")
        #expect(validateHostname("-foo.com") != nil, "invalid: leading hyphen in label")
        #expect(validateHostname("foo-.com") != nil, "invalid: trailing hyphen in label")
        #expect(validateHostname("foo..bar") != nil, "invalid: empty label")
        #expect(validateHostname(".foo") != nil, "invalid: leading dot")
        #expect(validateHostname("foo.") != nil, "invalid: trailing dot")
        #expect(validateHostname(String(repeating: "a", count: 64) + ".com") != nil, "invalid: 64-char label")
        #expect(validateHostname(String(repeating: "a.", count: 127) + "toolong") != nil, "invalid: >253 chars total")
        #expect(validateHostname("") != nil, "invalid: empty token")
    }

    // Regression documentation: WHY '#' must be rejected — a '#' written into a
    // hostname is re-read as a comment on the next parse, silently mangling the entry.
    @Test func hashRoundTripHazard() {
        let e = parseEntryBody("127.0.0.1\tfoo#bar", enabled: true)
        #expect(e?.hostnames ?? [] == ["foo"], "round-trip hazard: '#' splits hostname into comment")
        #expect(e?.comment ?? "" == "bar", "round-trip hazard: text after '#' becomes comment")
    }
}

@Suite struct NormalizeLineEndingsTests {
    @Test func conversions() {
        #expect(normalizeLineEndings("127.0.0.1\tlocalhost\r\n::1\tlocalhost\r\n")
                == "127.0.0.1\tlocalhost\n::1\tlocalhost\n", "CRLF file converts to LF")
        #expect(normalizeLineEndings("a\rb\rc") == "a\nb\nc", "lone CR converts to LF")
        #expect(normalizeLineEndings("a\r\nb\rc\n") == "a\nb\nc\n", "mixed CRLF and CR")
        #expect(normalizeLineEndings("127.0.0.1\tlocalhost\n")
                == "127.0.0.1\tlocalhost\n", "LF-only content unchanged")
        #expect(normalizeLineEndings("") == "", "empty string unchanged")
    }

    // Regression documentation: WHY this exists — the helper's validateContent
    // rejects \r as a control character, so an un-normalized CRLF import fails.
    @Test func noCarriageReturnsSurvive() {
        #expect(!normalizeLineEndings("127.0.0.1\thost\r\n").contains("\r"),
                "normalized content carries no \\r for the helper to reject")
    }
}
