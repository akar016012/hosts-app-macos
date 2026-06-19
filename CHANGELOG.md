# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- First-run onboarding flow: a welcome tour to set a local profile, pick a
  theme, and choose how edits unlock.
- Profile and appearance controls, including profile pictures, built-in themes,
  and a custom theme editor with per-token overrides.
- Full menu bar (File / Edit / Hosts) and a Settings window (⌘,).
- PIN unlock as an alternative to Touch ID, with a salted, iterated digest and
  brute-force lockout that escalates after repeated wrong attempts.
- Change history with one-click revert to earlier `/etc/hosts` snapshots, plus
  Undo Last Change.
- Read-only raw preview of the computed `/etc/hosts` with copy-to-clipboard.

### Changed

- Hardened privileged writes: symlink-safe atomic replace, content size cap,
  control-character rejection, replay protection (timestamps + persisted nonce
  set), and a defense-in-depth peer check in the helper.
- Refactored the monolithic source into `native/Core/` (logic) and `native/UI/`
  (SwiftUI) modules.
- Migrated the session signing key from the keychain to a file-based key
  (owner-only `0600`) to stop per-signature keychain prompts and improve helper
  stability.

## [1.0.0] - Unreleased

Initial public version (`CFBundleShortVersionString` 1.0).

- Native macOS SwiftUI app for viewing and editing `/etc/hosts`.
- Toggle, add, edit, and delete entries with IP + hostname validation.
- Search/filter, duplicate detection, and import/export.
- Privileged `/etc/hosts` writes through a signed LaunchDaemon helper registered
  via `SMAppService`, authorized by an ECDSA-signed, session-unlocked request.
- Automatic timestamped backups before every write.
- Flush DNS button.

[Unreleased]: https://github.com/adityakar/hosts-app/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/adityakar/hosts-app/releases/tag/v1.0.0
