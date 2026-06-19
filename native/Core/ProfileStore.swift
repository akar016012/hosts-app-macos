// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Local profile

// A lightweight, local-only identity for the app. There is no auth backend —
// "signing in" just means giving yourself a name (and optional email) so the
// header can show a personalized initials avatar and gather preferences and
// security controls under one Profile menu. Persisted in UserDefaults; the
// security primitives it surfaces (PIN, signing key) live in their own stores.
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    private static let nameKey = "hosts.profile.name"
    private static let emailKey = "hosts.profile.email"

    @Published var name: String {
        didSet { UserDefaults.standard.set(name, forKey: Self.nameKey) }
    }
    @Published var email: String {
        didSet { UserDefaults.standard.set(email, forKey: Self.emailKey) }
    }

    // The chosen profile picture, loaded from disk. Nil falls back to the
    // initials/glyph avatar. Persisted as a downscaled PNG alongside our other
    // app data so it survives relaunches but stays out of UserDefaults.
    @Published private(set) var avatar: NSImage?

    private init() {
        name = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
        email = UserDefaults.standard.string(forKey: Self.emailKey) ?? ""
        avatar = NSImage(contentsOf: Self.avatarURL)
    }

    // A profile is considered "signed in" once it has a name to show.
    var isSignedIn: Bool { !trimmedName.isEmpty }

    var hasAvatar: Bool { avatar != nil }

    // MARK: Avatar persistence

    private static var avatarURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("HostsEditor/avatar.png")
    }

    // Sets (or, with nil, clears) the profile picture. Incoming images are
    // cropped to a square and downscaled before writing so the on-disk file
    // stays small regardless of the source resolution.
    func setAvatar(_ image: NSImage?) {
        guard let image else {
            avatar = nil
            try? FileManager.default.removeItem(at: Self.avatarURL)
            return
        }
        let thumb = Self.squareThumbnail(image, side: 512)
        avatar = thumb
        guard let data = thumb.pngData() else { return }
        let dir = Self.avatarURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: Self.avatarURL)
    }

    // Center-crops to a square and scales to `side`×`side` so the circular
    // avatar always fills cleanly without distorting the source aspect ratio.
    private static func squareThumbnail(_ image: NSImage, side: CGFloat) -> NSImage {
        let src = image.size
        guard src.width > 0, src.height > 0 else { return image }
        let edge = min(src.width, src.height)
        let crop = NSRect(x: (src.width - edge) / 2, y: (src.height - edge) / 2,
                          width: edge, height: edge)
        let out = NSImage(size: NSSize(width: side, height: side))
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                   from: crop, operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    // Up to two letters: first letters of the first two words, else the first two
    // characters of a single word. Falls back to "?" so the avatar is never blank.
    var initials: String {
        let words = trimmedName.split(whereSeparator: { $0 == " " || $0 == "-" })
        let letters: [Character]
        if words.count >= 2 {
            letters = words.prefix(2).compactMap(\.first)
        } else if let first = words.first {
            letters = Array(first.prefix(2))
        } else {
            letters = []
        }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

// MARK: - Image helpers

extension NSImage {
    // PNG encoding of the bitmap, used to persist the avatar to disk.
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

// Presents a standard open panel filtered to image files and returns the chosen
// picture. Shared by the onboarding flow and the edit-profile sheet.
enum AvatarPicker {
    static func pick() -> NSImage? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        panel.message = "Choose a profile picture"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return NSImage(contentsOf: url)
    }
}
