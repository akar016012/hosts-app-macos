import Foundation

// Entry point for the standalone test suite. Compiled together with the pure-logic
// Core files (HostsParser, HostsModel, HostsHistory, PinStore) by test.sh.
// NOTE: this `main.swift` IS the program entry point — the app's @main in
// HostsEditor.swift is deliberately excluded from the test build to avoid a
// duplicate entry point.

let t = TestRunner()

// MARK: - 1. looksLikeIP

t.group("looksLikeIP")
t.expect(looksLikeIP("127.0.0.1"), "valid IPv4 loopback")
t.expect(looksLikeIP("192.168.1.1"), "valid IPv4 private")
t.expect(looksLikeIP("255.255.255.255"), "valid IPv4 broadcast")
t.expect(looksLikeIP("0.0.0.0"), "valid IPv4 all-zeros")
t.expect(!looksLikeIP("256.0.0.1"), "invalid: octet > 255")
t.expect(!looksLikeIP("1.2.3"), "invalid: too few octets")
t.expect(!looksLikeIP("1.2.3.4.5"), "invalid: too many octets")
t.expect(!looksLikeIP("1..3.4"), "invalid: empty octet")
t.expect(!looksLikeIP("1.2.3."), "invalid: trailing empty octet")
t.expect(!looksLikeIP(""), "invalid: empty string")
t.expect(looksLikeIP("::1"), "valid IPv6 loopback")
t.expect(looksLikeIP("fe80::1"), "valid IPv6 link-local")
t.expect(looksLikeIP("2001:db8::ff00:42:8329"), "valid full IPv6")
t.expect(looksLikeIP("fe80::1%lo0"), "valid IPv6 with zone id")
t.expect(!looksLikeIP("a:b"), "invalid: single-colon a:b is not IPv6")
t.expect(!looksLikeIP("example.com"), "invalid: hostname")
t.expect(!looksLikeIP("localhost"), "invalid: bare hostname")
// Document current behavior: the IPv6 regex permits non-hex zone chars only via
// [0-9a-zA-Z]; a `:`-containing string that matches the loose regex and has >=2
// colons passes even if not a strictly valid address.
t.expect(looksLikeIP(":::"), "current behavior: ':::' passes the loose IPv6 check")

// MARK: - 2. parseHosts / serializeHosts

t.group("parseHosts / serializeHosts")

// Enabled entry
do {
    let lines = parseHosts("127.0.0.1\tlocalhost\n")
    t.expectEqual(lines.count, 1, "enabled entry: one line")
    if case .entry(let e) = lines[0] {
        t.expect(e.enabled, "enabled entry: enabled flag true")
        t.expectEqual(e.ip, "127.0.0.1", "enabled entry: ip parsed")
        t.expectEqual(e.hostnames, ["localhost"], "enabled entry: hostnames parsed")
    } else {
        t.expect(false, "enabled entry: classified as .entry")
    }
}

// Disabled (commented-out) entry
do {
    let lines = parseHosts("# 10.0.0.5 myhost\n")
    if case .entry(let e) = lines[0] {
        t.expect(!e.enabled, "disabled entry: enabled flag false")
        t.expectEqual(e.ip, "10.0.0.5", "disabled entry: ip parsed")
        t.expectEqual(e.hostnames, ["myhost"], "disabled entry: hostnames parsed")
    } else {
        t.expect(false, "disabled entry: classified as .entry")
    }
}

// Pure comment line (not a host entry)
do {
    let lines = parseHosts("# This is just a comment\n")
    if case .comment(_, let text) = lines[0] {
        t.expectEqual(text, "# This is just a comment", "pure comment: preserved verbatim")
    } else {
        t.expect(false, "pure comment: classified as .comment")
    }
}

// Blank line in the middle
do {
    let lines = parseHosts("127.0.0.1 a\n\n127.0.0.2 b\n")
    t.expectEqual(lines.count, 3, "blank line: preserved between entries")
    if case .blank = lines[1] { t.expect(true, "blank line: middle is .blank") }
    else { t.expect(false, "blank line: middle is .blank") }
}

// Inline comment on an entry
do {
    let lines = parseHosts("127.0.0.1 myhost # inline note\n")
    if case .entry(let e) = lines[0] {
        t.expectEqual(e.comment, "inline note", "inline comment: captured into comment")
        t.expectEqual(e.hostnames, ["myhost"], "inline comment: hostname excludes comment")
    } else {
        t.expect(false, "inline comment: classified as .entry")
    }
}

// IPv6 zone entry
do {
    let lines = parseHosts("fe80::1%lo0 localhost\n")
    if case .entry(let e) = lines[0] {
        t.expectEqual(e.ip, "fe80::1%lo0", "ipv6 zone: ip with zone parsed")
        t.expect(isSystemDefault(e), "ipv6 zone: localhost@fe80::1%lo0 is system default")
    } else {
        t.expect(false, "ipv6 zone: classified as .entry")
    }
}

// Trailing blank line dropped by parser. A single trailing "\n" splits into an
// empty final component, which becomes a .blank that the parser removes — so a
// canonically-newline-terminated file yields only its content lines.
do {
    let lines = parseHosts("127.0.0.1 a\n")
    t.expectEqual(lines.count, 1, "trailing blank: single trailing newline dropped (only entry remains)")
    if case .entry = lines.last { t.expect(true, "trailing blank: last line is the entry") }
    else { t.expect(false, "trailing blank: last line is the entry") }
}
// Document current behavior: the parser strips only ONE trailing blank, so a file
// ending in TWO newlines keeps one interior blank line.
do {
    let lines = parseHosts("127.0.0.1 a\n\n")
    t.expectEqual(lines.count, 2, "trailing blank: only one trailing blank dropped (current behavior)")
    if case .blank = lines.last { t.expect(true, "trailing blank: a second trailing blank survives") }
    else { t.expect(false, "trailing blank: a second trailing blank survives") }
}

// serialize appends a trailing newline
do {
    let out = serializeHosts([.entry(HostEntry(enabled: true, ip: "127.0.0.1", hostnames: ["x"], comment: ""))])
    t.expect(out.hasSuffix("\n"), "serialize: appends trailing newline")
}

// Round-trip on a realistic /etc/hosts sample (lines already in canonical form).
// Because untouched entries preserve their `raw`, parse->serialize is byte-for-byte.
do {
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
    let roundTripped = serializeHosts(parseHosts(input))
    t.expectEqual(roundTripped, input, "round-trip: realistic sample is byte-for-byte preserved")
}

// MARK: - 3. ipKind / group / isSystemDefault

t.group("ipKind / group / isSystemDefault")

t.expectEqual(ipKind("0.0.0.0"), IPKind.block, "ipKind: 0.0.0.0 -> .block")
t.expectEqual(ipKind("255.255.255.255"), IPKind.broadcast, "ipKind: 255.255.255.255 -> .broadcast")
t.expectEqual(ipKind("127.0.0.1"), IPKind.loopback, "ipKind: 127.x -> .loopback")
t.expectEqual(ipKind("127.5.5.5"), IPKind.loopback, "ipKind: 127.5.5.5 -> .loopback")
t.expectEqual(ipKind("192.168.1.1"), IPKind.privateNet, "ipKind: 192.168.x -> .privateNet")
t.expectEqual(ipKind("10.1.2.3"), IPKind.privateNet, "ipKind: 10.x -> .privateNet")
t.expectEqual(ipKind("172.16.0.1"), IPKind.privateNet, "ipKind: 172.16.x -> .privateNet")
t.expectEqual(ipKind("172.31.255.1"), IPKind.privateNet, "ipKind: 172.31.x -> .privateNet")
t.expectEqual(ipKind("172.15.0.1"), IPKind.custom, "ipKind: 172.15.x -> .custom (outside private range)")
t.expectEqual(ipKind("172.32.0.1"), IPKind.custom, "ipKind: 172.32.x -> .custom (outside private range)")
t.expectEqual(ipKind("8.8.8.8"), IPKind.custom, "ipKind: public IP -> .custom")
t.expectEqual(ipKind("2001:db8::1"), IPKind.ipv6, "ipKind: IPv6 -> .ipv6")

// group(for:)
func entry(_ ip: String, _ names: [String], enabled: Bool = true) -> HostEntry {
    HostEntry(enabled: enabled, ip: ip, hostnames: names, comment: "")
}

t.expectEqual(group(for: entry("0.0.0.0", ["ads.tracker.com"])), HostGroup.blocking, "group: 0.0.0.0 -> .blocking")
t.expectEqual(group(for: entry("255.255.255.255", ["x"])), HostGroup.blocking, "group: 255.255.255.255 (non-broadcasthost) -> .blocking")
t.expectEqual(group(for: entry("127.0.0.1", ["devsite.test"])), HostGroup.localDev, "group: 127.x dev host -> .localDev")
t.expectEqual(group(for: entry("192.168.1.5", ["nas"])), HostGroup.homeNetwork, "group: 192.168.x -> .homeNetwork")
t.expectEqual(group(for: entry("10.0.0.5", ["server"])), HostGroup.homeNetwork, "group: 10.x -> .homeNetwork")
t.expectEqual(group(for: entry("172.20.0.1", ["server"])), HostGroup.homeNetwork, "group: 172.20.x -> .homeNetwork")
t.expectEqual(group(for: entry("8.8.8.8", ["public.example.com"])), HostGroup.remote, "group: custom public IP -> .remote")
t.expectEqual(group(for: entry("2001:db8::1", ["v6host"])), HostGroup.remote, "group: IPv6 -> .remote")

// isSystemDefault
t.expect(isSystemDefault(entry("127.0.0.1", ["localhost"])), "isSystemDefault: localhost@127.0.0.1")
t.expect(isSystemDefault(entry("::1", ["localhost"])), "isSystemDefault: localhost@::1")
t.expect(isSystemDefault(entry("fe80::1%lo0", ["localhost"])), "isSystemDefault: localhost@fe80::1%lo0")
t.expect(isSystemDefault(entry("255.255.255.255", ["broadcasthost"])), "isSystemDefault: broadcasthost")
t.expect(!isSystemDefault(entry("192.168.1.1", ["localhost"])), "isSystemDefault: localhost@192.168.1.1 is NOT system")
t.expect(!isSystemDefault(entry("8.8.8.8", ["example.com"])), "isSystemDefault: random host is NOT system")
t.expectEqual(group(for: entry("127.0.0.1", ["localhost"])), HostGroup.system, "group: localhost@127.0.0.1 -> .system")
t.expectEqual(group(for: entry("255.255.255.255", ["broadcasthost"])), HostGroup.system, "group: broadcasthost -> .system")

// MARK: - 4. HostSnapshot

t.group("HostSnapshot")

do {
    let content = "127.0.0.1 localhost\n255.255.255.255 broadcasthost\n# a comment\n\n10.0.0.5 host\n"
    let snap = HostSnapshot(label: "test", content: content)
    // 3 entries (localhost, broadcasthost, host); comment and blank are not entries.
    t.expectEqual(snap.entryCount, 3, "entryCount: computed from content (3 entries)")

    // Codable round-trip
    let encoded = try! JSONEncoder().encode(snap)
    let decoded = try! JSONDecoder().decode(HostSnapshot.self, from: encoded)
    t.expectEqual(decoded, snap, "Codable: round-trips equal")
    t.expectEqual(decoded.entryCount, 3, "Codable: entryCount preserved")
}

do {
    // Old JSON without entryCount must fall back to parsing on decode.
    let content = "127.0.0.1 localhost\n10.0.0.5 host\n"
    let oldJSON = """
    {"id":"\(UUID().uuidString)","timestamp":0,"label":"legacy","content":\(jsonString(content))}
    """
    let decoded = try! JSONDecoder().decode(HostSnapshot.self, from: Data(oldJSON.utf8))
    t.expectEqual(decoded.entryCount, 2, "legacy decode: entryCount falls back to parsing (2 entries)")
    t.expectEqual(decoded.label, "legacy", "legacy decode: label preserved")
}

// MARK: - 5. HistoryStore capping

t.group("HistoryStore")
// The improvement plan asked to verify capping behavior. After reading the source,
// HistoryStore exposes only `load`/`save`/`maxSnapshots` — there is NO public
// capping/trim function in Core; capping (if any) lives in the view/store layer
// which we don't compile here. So we assert the reachable surface: the constant.
t.expectEqual(HistoryStore.maxSnapshots, 50, "HistoryStore.maxSnapshots is 50")
// save/load round-trip through the temp HOME (Application Support under HOME).
do {
    let snaps = [
        HostSnapshot(label: "one", content: "127.0.0.1 a\n"),
        HostSnapshot(label: "two", content: "127.0.0.1 a\n10.0.0.1 b\n"),
    ]
    HistoryStore.save(snaps)
    // save() is async on a private queue; poll briefly for the file to appear.
    var loaded = HistoryStore.load()
    var tries = 0
    while loaded.count != 2 && tries < 50 { usleep(20_000); loaded = HistoryStore.load(); tries += 1 }
    t.expectEqual(loaded.count, 2, "HistoryStore: save/load round-trips snapshot count")
    if loaded.count == 2 {
        t.expectEqual(loaded[1].entryCount, 2, "HistoryStore: loaded snapshot keeps entryCount")
    }
}

// MARK: - 6. PinStore (runs under temp HOME set by test.sh)

t.group("PinStore")

// Sanity: confirm we are NOT writing to the user's real home dir. test.sh sets
// CFFIXED_USER_HOME to a mktemp dir, which NSHomeDirectory() honors. If this
// fails, the PinStore/HistoryStore tests below would touch the REAL home — abort
// loudly rather than risk clobbering the user's pin.json/history.json.
let home = NSHomeDirectory()
let isTempHome = home.contains("/var/folders/") || home.contains("/tmp/") || home.hasPrefix("/private/")
t.expect(isTempHome, "PinStore: running under a temporary HOME (\(home))")
if !isTempHome {
    print("\nABORT: NSHomeDirectory() is the real home — refusing to run filesystem tests that would clobber it.")
    print("Run via test.sh (which sets CFFIXED_USER_HOME), not the binary directly.")
    t.summary()
}

// validate
t.expect(PinStore.validate("123") != nil, "validate: rejects too-short (3 digits)")
t.expect(PinStore.validate("1234567890123") != nil, "validate: rejects too-long (13 digits)")
t.expect(PinStore.validate("12ab") != nil, "validate: rejects non-numeric")
t.expect(PinStore.validate("") != nil, "validate: rejects empty")
t.expect(PinStore.validate("1234") == nil, "validate: accepts 4-digit PIN")
t.expect(PinStore.validate("123456789012") == nil, "validate: accepts 12-digit PIN")

// set then verify
PinStore.clear()
do {
    try! PinStore.set("4242")
    t.expect(PinStore.isSet, "PinStore: isSet true after set")
    if case .ok = PinStore.verify("4242") { t.expect(true, "verify: correct PIN -> .ok") }
    else { t.expect(false, "verify: correct PIN -> .ok") }
}

// wrong PIN: remaining decreases; after maxAttempts -> lockedOut
PinStore.clear()
do {
    try! PinStore.set("4242")
    // First wrong attempt -> remaining = maxAttempts - 1 = 4
    if case .wrong(let r1) = PinStore.verify("0000") {
        t.expectEqual(r1, PinStore.maxAttempts - 1, "verify: 1st wrong -> remaining = maxAttempts-1")
    } else { t.expect(false, "verify: 1st wrong -> .wrong") }
    // Second wrong -> remaining decreases to 3
    if case .wrong(let r2) = PinStore.verify("0000") {
        t.expectEqual(r2, PinStore.maxAttempts - 2, "verify: 2nd wrong -> remaining decreases")
    } else { t.expect(false, "verify: 2nd wrong -> .wrong") }
    // Attempts 3, 4 still wrong; attempt 5 (== maxAttempts) -> lockedOut
    _ = PinStore.verify("0000") // 3rd
    _ = PinStore.verify("0000") // 4th
    if case .lockedOut(let secs) = PinStore.verify("0000") {
        t.expect(secs > 0, "verify: reaching maxAttempts -> .lockedOut with positive backoff")
    } else { t.expect(false, "verify: reaching maxAttempts -> .lockedOut") }
    // Document current behavior: while locked out, even the CORRECT PIN is
    // rejected with .lockedOut until the deadline passes.
    if case .lockedOut = PinStore.verify("4242") {
        t.expect(true, "verify: correct PIN during lockout still returns .lockedOut (current behavior)")
    } else { t.expect(false, "verify: correct PIN during lockout returns .lockedOut") }
}

// clear resets
PinStore.clear()
t.expect(!PinStore.isSet, "PinStore: isSet false after clear")

t.summary()
