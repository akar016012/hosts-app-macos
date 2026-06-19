# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-06-19

Initial public release (`CFBundleShortVersionString` 1.0). A native macOS
SwiftUI app for viewing and editing `/etc/hosts`.

### Added

- **Schemes**: named `/etc/hosts` environments that can be applied as a whole for
  one-click switching between Local dev, Staging, QA, Blocklist, and client
  setups. Includes a visual line diff preview before applying, optional DNS flush
  after apply, duplication, tags, notes, last-used tracking, and import/export of
  shareable `.hostsscheme` bundles. Applying snapshots the current file first, so
  every switch is reversible via History/Undo.
- **Menu-bar quick switch**: a macOS menu-bar item lists saved schemes and
  applies any of them without opening the main window; the active scheme is
  checkmarked. Schemes are reachable in-app via the Hosts → Schemes menu (⌘L).
- Toggle, add, edit, and delete entries with IP + hostname validation.
- Search/filter, duplicate detection, and whole-file import/export.
- First-run onboarding flow: a welcome tour to set a local profile, pick a
  theme, and choose how edits unlock.
- Profile and appearance controls, including profile pictures, built-in themes,
  and a custom theme editor with per-token overrides.
- Full menu bar (File / Edit / Hosts) and a Settings window (⌘,).
- Touch ID unlock, plus PIN unlock as an alternative, with a salted, iterated
  digest and brute-force lockout that escalates after repeated wrong attempts.
- Change history with one-click revert to earlier `/etc/hosts` snapshots, plus
  Undo Last Change.
- Read-only raw preview of the computed `/etc/hosts` with copy-to-clipboard.
- Automatic timestamped backups before every write.
- Flush DNS button.

### Security

- Privileged `/etc/hosts` writes through a signed LaunchDaemon helper registered
  via `SMAppService`, authorized by an ECDSA-signed, session-unlocked request.
- Hardened privileged writes: symlink-safe atomic replace, content size cap,
  control-character rejection, replay protection (timestamps + persisted nonce
  set), and a defense-in-depth peer check in the helper.

[Unreleased]: https://github.com/akar016012/hosts-app-macos/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/akar016012/hosts-app-macos/releases/tag/v1.0.0
