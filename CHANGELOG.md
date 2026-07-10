# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] - 2026-07-09

### Added

- **macOS password unlock.** The session can now be unlocked with the Mac login
  password — a third option alongside Touch ID and PIN, so Macs without Touch ID
  (or with a forgotten PIN) are never locked out. Available as a card in the
  unlock chooser, a "macOS Password" choice in the Default-unlock preference
  (profile menu, Settings, Lock pill, onboarding), and an "Unlock with macOS
  Password…" item in the Lock pill's context menu. The password is verified
  locally against the user's account via OpenDirectory and is never stored.
- **"Forgot PIN?" reset.** The PIN unlock sheet now offers a recovery path: after
  explaining that macOS authentication is required while locked, it verifies
  device ownership (login password, or Touch ID where available) and then clears
  the PIN record and its brute-force lockout state. The reset does not unlock the
  session — the user sets a new PIN and unlocks normally. This also recovers from
  a corrupt PIN record and from an active lockout.

### Fixed

- **PIN change/removal no longer possible while locked (session-lock bypass).**
  Settings (⌘,), the profile menu, and the PIN sheet all allowed replacing or
  removing the PIN without unlocking, letting anyone at the keyboard swap in
  their own PIN and unlock. Changing or removing an existing PIN now requires an
  unlocked session at every entry point, backed by fail-closed guards in the
  store itself; first-time setup remains available while locked. "Remove PIN"
  additionally asks for confirmation everywhere it appears.
- **Auto-lock “Never” persistence.** Choosing Never now remains selected after
  relaunch instead of silently reverting to the 30-minute default.
- **Theme changes no longer repeat one-time launch work.** Switching themes (or
  applying custom-theme edits) rebuilds the themed view tree by design; the
  one-time launch setup — hosts load, update probe, and the activity event
  monitor that feeds auto-lock — now lives outside that rebuilt subtree, so
  monitors no longer accumulate and the file isn't reloaded on every switch.
  Auto-unlock also re-checks session state, so users whose default unlock is
  Touch ID no longer get a surprise biometric prompt after changing theme.
- **Hostnames are validated in the entry editor.** A hostname containing `#`
  previously round-tripped into a truncated hostname plus a bogus comment;
  invalid characters and malformed labels are now rejected with an inline
  error before anything is written to `/etc/hosts`.

### Changed

- The profile dropdown is slightly wider so the Default-unlock row fits the new
  "macOS Password" option on one line, and onboarding's unlock picker uses
  compact segment labels. Onboarding also skips the PIN fields when a PIN
  already exists (replayed tours), pointing at the profile menu instead.

## [1.1.0] - 2026-06-24

### Added

- **"Update available" pill in the header.** When a newer version exists, an
  accent-colored pill (styled like the Lock pill) now appears in the header
  shortly after launch, reading "Update to \<version\>"; clicking it opens
  Sparkle's existing install flow. A silent appcast probe on first appear drives
  it, and the pill self-clears once the app is on the latest version — no
  unsolicited prompt at launch. The window's minimum width was widened to 1240 pt
  to keep the header controls uncrowded when the pill is shown.
- **Configurable auto-lock timeout.** The app can now lock itself automatically
  after a chosen period of inactivity. Options (Never / 1 min / 5 min / 15 min /
  30 min / 1 hour) are picked from the Auto-lock row in the profile Security
  section; the selection persists across launches. An NSEvent local monitor resets
  the countdown on any keyboard, mouse, or scroll interaction; a 60 s background
  timer fires the lock, clears Select mode, and shows a toast. Defaults to 30 min.

### Changed

- **Locked-state UI.** The app now visibly dims every blocked control when locked
  — entry and group toggles, Edit/Delete icon buttons, Flush DNS, New, Select,
  Schemes, History, and Raw — so it is immediately clear that changes require
  unlocking. Clicking a dimmed control still shows "Unlock to make changes." via
  the existing store guard.
- **No misleading toggle animation when locked.** A locked `ThemedToggle` no
  longer plays its splash animation; `commit()` returns before mutating when
  locked, so the knob stays put and the toast appears with no snap-back flicker.
- **Lock clears Select mode.** Locking (manually or via auto-lock) exits Select
  mode and clears the selection so the BulkBar cannot linger over blocked content.
- **Flush DNS guarded when locked.** Flush DNS is now wrapped in the same
  `guarded {}` path as New/Edit/Delete and shows "Unlock to make changes." rather
  than silently running while locked.

## [1.0.5] - 2026-06-24

### Changed

- Session unlock now runs its privileged-helper setup off the main thread, so the
  UI stays responsive during the occasionally multi-second helper registration and
  socket waits.

### Fixed

- **Privileged helper self-repair.** When macOS reported the helper as enabled but
  launchd refused to launch it — a stale Background Task Management record after an
  in-place update, surfacing as "Helper not responding after registration" — every
  unlock dead-ended. The app now detects the enabled-but-unreachable state and
  re-registers the helper automatically, recovering within a single unlock.
- Helper, Touch ID, signing, DNS-flush, and import/export errors now show
  actionable, plain-language guidance and no longer leak raw system error text; the
  privileged daemon's failures are translated from their structured codes into
  user-facing advice.

## [1.0.4] - 2026-06-22

### Added

- **In-app auto-update (Sparkle).** Hosts now checks for new versions on its own
  (daily) and on demand, then downloads and installs them in place — no manual
  re-download. Updates are EdDSA-signed and verified against a public key shipped
  in the app, and the update feed is an appcast published as a GitHub Release
  asset, so it tracks the latest release with no site edits. An ad-hoc
  "Check for Updates" action is available from the app menu, Settings → General,
  and the profile menu.
- **Notarized `.dmg` distribution.** Hosts is now downloadable as a signed,
  Developer ID–notarized, stapled disk image (drag-to-Applications, no Gatekeeper
  wall, works offline on first launch) alongside the build-from-source path. Added
  `native/release.sh`, which builds with a secure timestamp, notarizes both the app
  and the DMG, staples each, and emits a stable-named `HostsEditor.dmg` so the
  website's download button tracks the latest GitHub release with no edits.

### Changed

- Session unlock now runs its privileged-helper setup off the main thread, so the
  UI stays responsive during the occasionally multi-second helper registration and
  socket waits.
- `native/build.sh` now stamps the bundle version from `APP_VERSION` (defaults to
  `1.0`; release builds derive it from the git tag) and adds a secure `--timestamp`
  to signatures when `RELEASE=1`, as required for notarization.
- `native/build.sh` downloads (checksum-pinned) and embeds Sparkle 2.9.3 into the
  bundle — signing its nested helpers inside-out for notarization — and stamps the
  Sparkle keys (appcast feed URL, public EdDSA key, daily check interval) into
  Info.plist. `native/release.sh` generates and signs `appcast.xml` after stapling;
  it must be uploaded alongside the DMGs for in-app updates to resolve.

### Fixed

- **Privileged helper self-repair.** When macOS reported the helper as enabled but
  launchd refused to launch it — a stale Background Task Management record after an
  in-place update, surfacing as "Helper not responding after registration" — every
  unlock dead-ended. The app now detects the enabled-but-unreachable state and
  re-registers the helper automatically, recovering within a single unlock.
- Helper, Touch ID, signing, DNS-flush, and import/export errors now show
  actionable, plain-language guidance and no longer leak raw system error text; the
  privileged daemon's failures are translated from their structured codes into
  user-facing advice.
- The About panel now reads the real `CFBundleShortVersionString` instead of a
  hardcoded `1.0`, so it matches the running build (and Sparkle's current version).

## [1.0.3] - 2026-06-19

### Fixed

- Onboarding's helper step now reflects approval after the user returns from
  System Settings: status was only re-read in `.onAppear`, which doesn't fire on
  refocus, so enabling "Hosts" in Login Items left the step (and the "You're all
  set" summary) stuck on "Helper not enabled". Both steps now re-poll on
  `didBecomeActive`.
- Duplicate-hostname detection now counts a hostname repeated across enabled
  entries on the same IP, not just one mapped to conflicting IPs — so the
  "N duplicate hosts" warning no longer silently shows nothing for the common
  case. Collisions among macOS system defaults (e.g. `localhost` on `::1` and
  `fe80::1%lo0`) stay exempt until a user-defined entry is involved.

### Changed

- Renamed the app and helper bundle-identifier prefix from `com.aditya.*` to
  `com.etchosts.*` across code, build, and docs, so the shipping identifiers no
  longer carry a personal namespace. Includes the keychain key tags (with legacy
  tags retained for migration), the launchd plist, `CFBundleIdentifier`, and the
  pinned `codesign --identifier`.
- Bumped the main window's minimum height from 600 to 720 for more editor room
  on launch.

## [1.0.2] - 2026-06-19

### Security

- **Peer code-signature verification in the helper.** Before reading any request,
  the LaunchDaemon now resolves the peer's audit token (`LOCAL_PEERTOKEN`) and
  requires the connecting process to be the app itself — code-signed by the same
  Team Identifier as the helper, with the app's bundle id, chained to Apple's
  anchor. This applies to first-use enrollment too, so possession of the session
  signing key is no longer sufficient to drive a privileged write or plant the
  trust anchor. Root peers are exempt; unsigned/ad-hoc dev builds fall back to the
  UID + signature gates.

### Added

- **Wire-protocol version negotiation.** Write/enroll requests carry a `protocol`
  field; the helper rejects a mismatched version with a `protocol_mismatch` code
  (an absent field is treated as v1 for backward compatibility).
- **`payload_too_large` helper error.** Oversized requests now return a clear code
  instead of being misreported as malformed.

### Fixed

- Large hosts files no longer fail silently: the helper's socket read limit was
  below the advertised 8 MB content limit (base64 inflation pushed real payloads
  past the cap), truncating big blocklists into a misleading "malformed request".
  The read limit now sits above the maximum encoded payload.
- Stricter IPv6 validation: address parsing uses `inet_pton` (with zone-id
  handling) instead of a loose regex, so malformed pseudo-addresses like `:::` are
  no longer treated as host entries.
- Hardened crypto error paths: `CFError` values are no longer force-unwrapped, so a
  `SecKey`/`SecCode` failure that returns no error object can't crash the app or
  daemon.

### Changed

- The diff preview's LCS table now uses a flat `Int32` buffer with a tighter line
  budget, cutting worst-case memory for large scheme diffs by roughly an order of
  magnitude.
- Launch auto-unlock now triggers only when Touch ID is the explicitly chosen
  default, so users who haven't picked a preference aren't surprised by a biometric
  prompt at startup.
- `ProfileStore` is now main-actor isolated, consistent with the other stores.

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

[Unreleased]: https://github.com/akar016012/hosts-app-macos/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/akar016012/hosts-app-macos/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/akar016012/hosts-app-macos/compare/v1.0.5...v1.1.0
[1.0.5]: https://github.com/akar016012/hosts-app-macos/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/akar016012/hosts-app-macos/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/akar016012/hosts-app-macos/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/akar016012/hosts-app-macos/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/akar016012/hosts-app-macos/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/akar016012/hosts-app-macos/releases/tag/v1.0.0
