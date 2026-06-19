// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Foundation

// MARK: - Change history

// A point-in-time snapshot of the full /etc/hosts contents. Snapshots are
// captured after every successful write (and on launch) so the user can review
// past versions and revert to any of them.
struct HostSnapshot: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let label: String
    let content: String
    // Computed once at capture and stored, so the history list doesn't re-parse
    // the full file for every visible row on every redraw.
    let entryCount: Int

    init(id: UUID = UUID(), timestamp: Date = Date(), label: String, content: String) {
        self.id = id
        self.timestamp = timestamp
        self.label = label
        self.content = content
        self.entryCount = HostSnapshot.countEntries(content)
    }

    // Reuse the parser so the count matches what the list view shows.
    private static func countEntries(_ content: String) -> Int {
        parseHosts(content).reduce(0) { n, line in
            if case .entry = line { return n + 1 } else { return n }
        }
    }

    // entryCount was added later; snapshots persisted by older builds won't have
    // it, so fall back to parsing on decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        label = try c.decode(String.self, forKey: .label)
        content = try c.decode(String.self, forKey: .content)
        entryCount = try c.decodeIfPresent(Int.self, forKey: .entryCount) ?? HostSnapshot.countEntries(content)
    }
}

// File-backed persistence in the app's own Application Support directory — no
// privileges needed to read or write our own data, unlike /etc/hosts itself.
enum HistoryStore {
    static let maxSnapshots = 50

    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("HostsEditor", isDirectory: true)
    }
    private static var fileURL: URL { dir.appendingPathComponent("history.json") }
    // Serializes writes and keeps the (potentially large) JSON encode + disk write
    // off the main actor so big hosts files don't stutter the UI on every change.
    private static let ioQueue = DispatchQueue(label: "com.aditya.hostseditor.history.io")

    static func load() -> [HostSnapshot] {
        guard let data = try? Data(contentsOf: fileURL),
              let snaps = try? JSONDecoder().decode([HostSnapshot].self, from: data) else { return [] }
        return snaps
    }

    static func save(_ snaps: [HostSnapshot]) {
        ioQueue.async {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(snaps) else { return }
            try? data.write(to: fileURL)
        }
    }
}
