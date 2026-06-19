// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Foundation
import SwiftUI

// MARK: - Host schemes

// A named, self-contained /etc/hosts body the user can switch to as a whole —
// e.g. "Client A staging", "Local Docker", "QA cluster", "Ad blocking". Applying a
// scheme writes its `content` over /etc/hosts through the same privileged, backed-up
// write path as any edit, so switching is reversible via history/undo. This is the
// "environment switching" concept and is distinct from ProfileStore (the local
// user identity / avatar).
struct Scheme: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var note: String
    var tags: [String]
    var content: String          // the full hosts-file body this scheme applies
    var createdAt: Date
    var lastAppliedAt: Date?

    init(id: UUID = UUID(), name: String, note: String = "", tags: [String] = [],
         content: String, createdAt: Date = Date(), lastAppliedAt: Date? = nil) {
        self.id = id; self.name = name; self.note = note; self.tags = tags
        self.content = content; self.createdAt = createdAt; self.lastAppliedAt = lastAppliedAt
    }

    // Reuse the parser so the count matches what the editor/list shows. Computed
    // (not stored) so it can never drift from `content`.
    var entryCount: Int {
        parseHosts(content).reduce(0) { n, line in
            if case .entry = line { return n + 1 } else { return n }
        }
    }
}

@MainActor
final class SchemeStore: ObservableObject {
    static let shared = SchemeStore()

    // Bundle file extension used for import/export so schemes can be shared.
    static let bundleExtension = "hostsscheme"

    @Published private(set) var schemes: [Scheme] = []

    // nonisolated: pure path math touching no actor state, so the background IO
    // queue can reference them without hopping to the main actor.
    nonisolated private static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HostsEditor", isDirectory: true)
    }
    nonisolated private static var fileURL: URL { dir.appendingPathComponent("schemes.json") }
    private let ioQueue = DispatchQueue(label: "com.aditya.hostseditor.schemes.io")

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder.scheme.decode([Scheme].self, from: data) {
            schemes = decoded
        }
    }

    // The scheme whose content currently matches /etc/hosts, if any — used to mark
    // the active scheme in the UI and the menu bar.
    func activeScheme(matching rawText: String) -> Scheme? {
        schemes.first { $0.content == rawText }
    }

    // MARK: CRUD

    func add(_ scheme: Scheme) {
        schemes.insert(scheme, at: 0)
        persist()
    }

    func update(_ scheme: Scheme) {
        guard let i = schemes.firstIndex(where: { $0.id == scheme.id }) else { return }
        schemes[i] = scheme
        persist()
    }

    func delete(_ id: UUID) {
        schemes.removeAll { $0.id == id }
        persist()
    }

    @discardableResult
    func duplicate(_ id: UUID) -> Scheme? {
        guard let src = schemes.first(where: { $0.id == id }) else { return nil }
        let copy = Scheme(name: uniqueName(from: "\(src.name) copy"), note: src.note,
                          tags: src.tags, content: src.content)
        schemes.insert(copy, at: 0)
        persist()
        return copy
    }

    // Records that a scheme was just applied (moves it to the top for recency and
    // stamps the time). No-op if the id is unknown (e.g. applying ad-hoc content).
    func markApplied(_ id: UUID) {
        guard let i = schemes.firstIndex(where: { $0.id == id }) else { return }
        schemes[i].lastAppliedAt = Date()
        let s = schemes.remove(at: i)
        schemes.insert(s, at: 0)
        persist()
    }

    // Ensure a new scheme name doesn't collide with an existing one by appending a
    // counter — keeps the list readable and import predictable.
    func uniqueName(from base: String) -> String {
        let existing = Set(schemes.map { $0.name })
        if !existing.contains(base) { return base }
        var n = 2
        while existing.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    // MARK: Import / export bundles (JSON)

    func exportBundle(_ ids: [UUID], to url: URL) throws {
        let chosen = schemes.filter { ids.contains($0.id) }
        let data = try JSONEncoder.pretty.encode(chosen)
        try data.write(to: url, options: .atomic)
    }

    // Import schemes from a bundle, giving each a fresh id and a de-duplicated name
    // so importing never overwrites or clashes with an existing scheme. Returns the
    // number imported.
    @discardableResult
    func importBundle(from url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        let incoming = try JSONDecoder.scheme.decode([Scheme].self, from: data)
        for s in incoming {
            let fresh = Scheme(name: uniqueName(from: s.name), note: s.note, tags: s.tags, content: s.content)
            schemes.insert(fresh, at: 0)
        }
        persist()
        return incoming.count
    }

    private func persist() {
        let snapshot = schemes
        ioQueue.async {
            try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
            guard let data = try? JSONEncoder.pretty.encode(snapshot) else { return }
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}

extension JSONEncoder {
    // Pretty + stable key order so exported bundles diff cleanly in version control.
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    // Pairs with JSONEncoder.pretty's iso8601 dates so persisted/imported schemes
    // round-trip their createdAt/lastAppliedAt correctly.
    static var scheme: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
