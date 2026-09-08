// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Foundation
import CryptoKit

@main struct WriteSafetyTests {
    @MainActor static func main() async throws {
        // Check isolation before initializing any persistence-backed store.
        guard let root = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"],
              URL(fileURLWithPath: root).standardizedFileURL == URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL, root.contains("hosts-write-tests.") else {
            fatalError("Run through scripts/test.sh with its isolated home")
        }
        let t = TestRunner()
        let path = root + "/hosts"
        let original = "0.0.0.0 baseline.test\n0.0.0.0 blocked.test\n"
        let external = original + "0.0.0.0 external.test\n"
        func put(_ content: String) throws { try Data(content.utf8).write(to: URL(fileURLWithPath: path), options: .atomic) }
        func disk() throws -> String { try String(contentsOfFile: path, encoding: .utf8) }
        func hash(_ content: String) -> String {
            SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        func wait(_ store: HostsStore) async {
            for _ in 0..<200 where store.isWriting { try? await Task.sleep(nanoseconds: 5_000_000) }
            t.expect(!store.isWriting, "write completed within deadline")
        }

        t.group("Helper baseline checks")
        try put(external)
        do {
            try writeHostsFile(content: original, expectedHash: hash(original), path: path, backupDirectory: path + "-backups")
            t.expect(false, "stale baseline rejected")
        } catch HostsFileConflict.changed { t.expect(true, "stale baseline rejected") }
        t.expectEqual(try disk(), external, "external bytes preserved")
        t.expect(!FileManager.default.fileExists(atPath: path + "-backups"), "conflict rejected before backup")
        try writeHostsFile(content: original, expectedHash: hash(external), path: path, backupDirectory: path + "-backups")
        t.expectEqual(try disk(), original, "matching baseline can write")
        let backups = try FileManager.default.contentsOfDirectory(atPath: path + "-backups")
        t.expectEqual(try String(contentsOfFile: path + "-backups/" + backups[0], encoding: .utf8), external, "backup contains exact external baseline")
        // Swift String equality treats these as equal; the disk precondition must not.
        try put("# e\u{301}\r\n")
        do {
            try writeHostsFile(content: original, expectedHash: hash("# é\r\n"), path: path, backupDirectory: path + "-backups")
            t.expect(false, "byte-distinct Unicode baseline rejected")
        } catch HostsFileConflict.changed { t.expect(true, "byte-distinct Unicode baseline rejected") }
        try FileManager.default.removeItem(atPath: path)
        do {
            try writeHostsFile(content: original, expectedHash: hash(""), path: path, backupDirectory: path + "-backups")
            t.expect(false, "missing file fails closed")
        } catch { t.expect(true, "missing file fails closed") }
        t.expect(!FileManager.default.fileExists(atPath: path), "missing file is not recreated")

        t.group("Store external changes and pending writes")
        try put(original)
        await HelperGateway.shared.configure(path: path)
        let store = HostsStore(path: path)
        store.load()
        store.sessionUnlocked = true
        let ids = store.entries.map(\.id)
        store.refreshFromDisk()
        t.expectEqual(store.entries.map(\.id), ids, "unchanged activation preserves row identities")
        store.selection = [ids[1]]
        try put(external)
        store.refreshFromDisk()
        t.expectEqual(store.rawText, external, "activation loads external changes")
        t.expect(store.selection.isEmpty, "refresh clears stale selection")
        t.expectEqual(store.history.first?.content, external, "external version recorded in History")
        store.toggle(store.entries[1].id)
        await wait(store)
        t.expect(try disk().contains("external.test"), "unrelated toggle preserves refreshed external entry")
        t.expectEqual(store.history[1].content, external, "Undo baseline includes external edit")
        store.undoLast()
        await wait(store)
        t.expectEqual(try disk(), external, "Undo restores external baseline")

        // Each UI write path must carry its original baseline, even if disk changes
        // after the operation is submitted. No stale request may be retried.
        for operation in ["row", "replacement", "history"] {
            try put(original)
            store.refreshFromDisk()
            let before = await HelperGateway.shared.count()
            switch operation {
            case "row": store.toggle(store.entries[1].id)
            case "replacement": store.replaceAll(with: "# replacement\n", label: "replacement")
            default: store.revert(to: HostSnapshot(label: "old", content: "# history\n"))
            }
            t.expect(!store.editingReady, "\(operation): controls disabled during write")
            store.add(ip: "0.0.0.0", hostnames: ["queued.test"], comment: "", enabled: true)
            try put(external)
            store.refreshFromDisk() // Must defer without changing the expected baseline.
            await wait(store)
            t.expectEqual(try disk(), external, "\(operation): stale write preserves disk")
            t.expectEqual(store.rawText, external, "\(operation): conflict reloads model")
            t.expectEqual(serializeHosts(store.lines), external, "\(operation): optimistic mutation discarded")
            t.expectEqual(store.history.first?.content, external, "\(operation): conflict records live baseline")
            t.expect(store.toast?.msg.contains("not saved") == true, "\(operation): conflict explained")
            t.expectEqual(await HelperGateway.shared.count(), before + 1, "\(operation): no queued write or automatic retry")
        }
        let replacement = "# committed replacement\n" + external
        store.replaceAll(with: replacement, label: "replacement")
        store.toggle(store.entries[1].id)
        await wait(store)
        t.expectEqual(try disk(), replacement, "pending row edit cannot undo successful replacement")
        t.expectEqual(serializeHosts(store.lines), replacement, "replacement model matches disk")
        await HelperGateway.shared.configure(path: path, fail: true)
        store.toggle(store.entries[1].id)
        await wait(store)
        t.expectEqual(serializeHosts(store.lines), replacement, "ordinary failure restores committed model")
        t.expectEqual(store.rawText, replacement, "ordinary failure retains baseline")
        t.expect(store.editingReady, "editing resumes after failure")

        try FileManager.default.removeItem(atPath: path)
        store.refreshFromDisk()
        t.expect(!store.editingReady, "unreadable baseline blocks edits")
        try put(original)
        store.refreshFromDisk()
        t.expect(store.editingReady, "successful reload restores editing")
        t.summary()
    }
}
