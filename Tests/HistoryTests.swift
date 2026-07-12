// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Foundation
import Testing

@Suite struct HostSnapshotTests {
    @Test func entryCountAndCodableRoundTrip() throws {
        let content = "127.0.0.1 localhost\n255.255.255.255 broadcasthost\n# a comment\n\n10.0.0.5 host\n"
        let snap = HostSnapshot(label: "test", content: content)
        // 3 entries (localhost, broadcasthost, host); comment and blank are not entries.
        #expect(snap.entryCount == 3, "entryCount: computed from content (3 entries)")

        let encoded = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(HostSnapshot.self, from: encoded)
        #expect(decoded == snap, "Codable: round-trips equal")
        #expect(decoded.entryCount == 3, "Codable: entryCount preserved")
    }

    // Old JSON without entryCount must fall back to parsing on decode.
    @Test func legacyDecodeFallsBackToParsing() throws {
        let content = "127.0.0.1 localhost\n10.0.0.5 host\n"
        let oldJSON = """
        {"id":"\(UUID().uuidString)","timestamp":0,"label":"legacy","content":\(jsonString(content))}
        """
        let decoded = try JSONDecoder().decode(HostSnapshot.self, from: Data(oldJSON.utf8))
        #expect(decoded.entryCount == 2, "legacy decode: entryCount falls back to parsing (2 entries)")
        #expect(decoded.label == "legacy", "legacy decode: label preserved")
    }
}

// Touches history.json under NSHomeDirectory() — serialized, and guarded so it
// can only ever run against the scheme's throwaway CFFIXED_USER_HOME.
@Suite(.serialized) struct HistoryStoreTests {
    init() { requireTemporaryHome() }

    // HistoryStore exposes only `load`/`save`/`maxSnapshots` — there is NO public
    // capping/trim function in Core; capping (if any) lives in the view/store layer
    // which isn't compiled here. So assert the reachable surface: the constant.
    @Test func maxSnapshotsConstant() {
        #expect(HistoryStore.maxSnapshots == 50, "HistoryStore.maxSnapshots is 50")
    }

    @Test func saveLoadRoundTrip() {
        let snaps = [
            HostSnapshot(label: "one", content: "127.0.0.1 a\n"),
            HostSnapshot(label: "two", content: "127.0.0.1 a\n10.0.0.1 b\n"),
        ]
        HistoryStore.save(snaps)
        // save() is async on a private queue; poll briefly for the file to appear.
        var loaded = HistoryStore.load()
        var tries = 0
        while loaded.count != 2 && tries < 50 { usleep(20_000); loaded = HistoryStore.load(); tries += 1 }
        #expect(loaded.count == 2, "HistoryStore: save/load round-trips snapshot count")
        if loaded.count == 2 {
            #expect(loaded[1].entryCount == 2, "HistoryStore: loaded snapshot keeps entryCount")
        }
    }
}
