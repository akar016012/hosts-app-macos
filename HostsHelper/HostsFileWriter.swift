// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Foundation
import CryptoKit
import Darwin

struct WriteError: LocalizedError { let message: String; var errorDescription: String? { message } }
enum HostsFileConflict: Error { case changed }

private func requireHostsBaseline(_ data: Data, expectedHash: String) throws {
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard hash == expectedHash else { throw HostsFileConflict.changed }
}

// Keep only the most recent N timestamped backups (filenames sort chronologically).
private func pruneBackups(in backupDirectory: String, keep: Int = 20) {
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: backupDirectory) else { return }
    let baks = files.filter { $0.hasPrefix("hosts-") && $0.hasSuffix(".bak") }.sorted()
    guard baks.count > keep else { return }
    for f in baks.prefix(baks.count - keep) {
        try? FileManager.default.removeItem(atPath: "\(backupDirectory)/\(f)")
    }
}

func writeHostsFile(content: String, expectedHash: String, path: String, backupDirectory: String) throws {
    // Read failures (including a missing file) fail closed.
    let current = try Data(contentsOf: URL(fileURLWithPath: path))
    try requireHostsBaseline(current, expectedHash: expectedHash)
    try? FileManager.default.createDirectory(atPath: backupDirectory, withIntermediateDirectories: true,
                                             attributes: [.posixPermissions: 0o700])
    // Back up as raw bytes (not UTF-8 text) so a hand-edited or non-UTF-8 file is
    // preserved verbatim — and fail closed: never overwrite an existing hosts file
    // whose backup couldn't be taken.
    let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
    do {
        try current.write(to: URL(fileURLWithPath: "\(backupDirectory)/hosts-\(stamp).bak"), options: .atomic)
    } catch {
        throw WriteError(message: "could not create backup: \(error.localizedDescription)")
    }
    pruneBackups(in: backupDirectory)

    // Symlink-safe atomic replace: write a fresh temp file in the same directory
    // with O_NOFOLLOW|O_EXCL (so an attacker-planted symlink can't redirect the
    // write), then rename() over the target. rename replaces the name itself, so
    // even if /etc/hosts were a symlink it's atomically swapped for a real file.
    let tmpPath = path + ".hostsedit.tmp"
    unlink(tmpPath)
    let fd = open(tmpPath, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_EXCL, 0o644)
    if fd < 0 { throw WriteError(message: "open temp failed (errno \(errno))") }
    let bytes = Array(content.utf8)
    let written = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, bytes.count) }
    fchmod(fd, 0o644)
    close(fd)
    guard written == bytes.count else {
        unlink(tmpPath)
        throw WriteError(message: "short write")
    }
    // Check again after backup/temp-file preparation, immediately before rename.
    do {
        try requireHostsBaseline(Data(contentsOf: URL(fileURLWithPath: path)), expectedHash: expectedHash)
    } catch {
        unlink(tmpPath)
        throw error
    }
    if rename(tmpPath, path) != 0 {
        let e = errno
        unlink(tmpPath)
        throw WriteError(message: "rename failed (errno \(e))")
    }
    chown(path, 0, 0)   // keep canonical root:wheel ownership
}

