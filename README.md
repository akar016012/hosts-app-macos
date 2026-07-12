# Hosts — SwiftUI `/etc/hosts` editor

A native macOS SwiftUI app for viewing and editing `/etc/hosts`: switch whole
environments with named schemes, add, edit, enable/disable, delete entries,
search/filter, preview the raw file, and flush the macOS DNS cache.

## Demo

A guided tour of the real app — from first-run onboarding to schemes, visual
diffs, DNS flush, Touch ID unlock, and the custom theme editor.



https://github.com/user-attachments/assets/befea907-c00f-447e-8e58-8ce6e0ec9176



## Features

- **Schemes** — save named `/etc/hosts` environments (Local dev, Staging, QA,
  Blocklist…) and switch between them in one click. Applying shows a **visual
  diff** of exactly what will change before writing, with an optional DNS flush;
  the previous file is snapshotted first, so every switch is reversible. Schemes
  can be duplicated, tagged, and imported/exported as shareable `.hostsscheme`
  bundles.
- **Menu-bar quick switch** — apply any scheme from the macOS menu bar without
  opening the main window; the active scheme is checkmarked.
- **Toggle entries on/off** without deleting them (comments the line out).
- **Add / edit / delete** entries with IP + hostname validation.
- **Search & filter** by IP, hostname, or comment; filter by active/disabled.
- **Duplicate detection** — flags a hostname that appears in more than one enabled entry for the same IP version (IPv4/IPv6). Distinct macOS default entries (e.g. `localhost`) are ignored, but repeats or user entries still warn.
- **Import / export** an entire hosts file (File menu).
- **Raw preview** — view the full computed `/etc/hosts` and copy it to the
  clipboard (read-only; edits are made through the structured entry list).
- **Touch ID or PIN session unlock** for edits through a privileged helper, with
  brute-force lockout after repeated wrong PIN attempts.
- **Change history** with one-click revert to earlier `/etc/hosts` snapshots, and
  Undo Last Change (⌥⌘Z).
- **Full menu bar** (File / Edit / Hosts) and a **Settings window** (⌘,).
- **Profile and appearance controls** with built-in themes and a custom theme editor.
- **Automatic backups** — a timestamped copy is saved before every write.
- **Flush DNS** button (macOS).
- No web server, browser UI, Node.js, or npm dependencies.

### Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New entry | ⌘N |
| Import / Export hosts file | ⌘O / ⇧⌘E |
| Find | ⌘F |
| Schemes | ⌘L |
| Raw preview / History | ⌘R / ⌘Y |
| Undo last change | ⌥⌘Z |
| Flush DNS cache | ⌘K |
| Settings | ⌘, |

## Install

**Download the latest signed, notarized release:**

→ **[Download Hosts for macOS (.dmg)](https://etc-hosts.com/#install)**

Open the `.dmg`, drag **HostsEditor** onto **Applications**, then launch it from
Applications. The app is signed with a Developer ID and notarized by Apple, so
there's no Gatekeeper "unidentified developer" wall — and because the ticket is
stapled, the first launch works even offline.

### Prefer to build it yourself?

You can instead build Hosts from source and sign it with **your own free Apple
signing identity** (any Apple ID works — no paid Developer Program needed). It
takes about five minutes.

→ **Step-by-step guide:** [docs/build-from-source.md](docs/build-from-source.md)

## Build

Open `etc-hosts.xcodeproj` in Xcode and press **⌘R**, or from the command line:

```bash
xcodebuild -project etc-hosts.xcodeproj -scheme etc-hosts -configuration Debug build
```

The build produces `HostsEditor.app` (in Xcode's DerivedData products directory)
with the privileged helper and its launchd plist embedded, and Sparkle pulled in
via Swift Package Manager.

The bundle is signed with a real signing identity (not ad-hoc) because
`SMAppService` refuses to register an ad-hoc–signed daemon. A **free Apple
Development certificate** (created from a free Apple ID "Personal Team" in Xcode)
is enough to build and run locally — select **your own team** under **Signing &
Capabilities** for both targets, or pass it on the command line without editing
the project:

```bash
xcodebuild -project etc-hosts.xcodeproj -scheme etc-hosts -configuration Debug \
  DEVELOPMENT_TEAM=YOURTEAMID build
``` A paid **Developer ID** + notarization is only
needed to distribute the app to other Macs — that's how the published `.dmg` above
is produced, via Xcode's Archive → Organizer flow (see
[docs/release.md](docs/release.md)).

## Run

Run the app from Xcode (**⌘R**), or open the built `HostsEditor.app` from the
products directory.

On first launch, the app shows a welcome tour where you can set a local profile,
pick a theme, and choose how edits unlock. Returning users unlock the edit
session with Touch ID or an app PIN; edits stay unlocked for the rest of that
app session.

During launch/setup, the app registers its bundled privileged helper through
`SMAppService`. The **first** time, macOS leaves it pending and the app opens
**System Settings → Login Items** so you can enable "Hosts"; unlock again
afterwards to finish. There is no administrator-password prompt for helper
setup. Editing controls stay disabled until the helper is enabled and the app's
signing key is enrolled with it.

Touch ID must be available and enrolled on the Mac for Touch ID unlock. If you
add or remove fingerprints in System Settings, reset the session key from the
profile or lock menu so the helper receives the fresh public key.

## How it works

- `etc-hosts/HostsEditor.swift` — the SwiftUI app entry point.
- `etc-hosts/Core/` — app state, parsing, host grouping, session signing, local
  history, and privileged-helper communication.
- `etc-hosts/UI/` — SwiftUI screens, sheets, row components, themes, and button
  styles.
- `HostsHelper/main.swift` — the privileged LaunchDaemon helper (its own Xcode
  target). It lives inside the app bundle (`Contents/MacOS`) with its launchd
  plist at `Contents/Library/LaunchDaemons`, is registered/unregistered via
  `SMAppService` (see `etc-hosts/Core/ServiceManager.swift`), and only writes
  `/etc/hosts` after validating a request signed by the app's session key. The
  trusted public key is recorded on first use via an `enroll` message over the
  helper socket. Before reading any request the helper also verifies, via the
  peer's audit token, that the connecting process is the app itself —
  code-signed by the same team as the helper — so the signing key alone is not
  enough to drive a write.
- `etc-hosts.xcodeproj` — the Xcode project: the `etc-hosts` app target embeds
  the `HostsHelper` target's binary in `Contents/MacOS` and the daemon plist in
  `Contents/Library/LaunchDaemons`, and signs everything with a real signing
  identity (hardened runtime).

Disabled entries are stored as commented-out lines.

## Stored data and config

The app intentionally keeps runtime state in standard macOS locations:

- `/etc/hosts` — the file being edited. Disabled entries are commented out in
  this file.
- `~/Library/Preferences/com.etchosts.hostseditor.plist` — `UserDefaults` values,
  including onboarding completion, local profile name/email, selected theme,
  custom theme data, and the default unlock method.
- `~/Library/Application Support/HostsEditor/history.json` — in-app change
  history, capped at the most recent 50 snapshots.
- `~/Library/Application Support/HostsEditor/pin.json` — salted PBKDF2 PIN
  digest for PIN unlock. The PIN itself is never stored.
- `~/Library/Application Support/HostsEditor/session-signing.key` — owner-only
  private key used to sign write requests sent to the privileged helper.

The helper executable and its launchd plist now live **inside the app bundle**
(`Contents/MacOS/com.etchosts.hostshelper` and
`Contents/Library/LaunchDaemons/com.etchosts.hostshelper.plist`) and are managed by
`SMAppService` — they are no longer copied into `/Library/PrivilegedHelperTools`
or `/Library/LaunchDaemons`. Moving or deleting the app effectively unregisters
the daemon. The "Remove Privileged Helper…" item in the **Hosts** menu (or the
toggle in System Settings → Login Items) unregisters it.

The running helper still keeps root-owned trust state:

- `/Library/Application Support/HostsHelper/pubkey` — public key trusted by the
  helper, recorded on first-use enrollment.
- `/Library/Application Support/HostsHelper/uid` — local user ID allowed to
  drive the helper.
- `/Library/Application Support/HostsHelper/backups/` — timestamped backups
  captured before each write.
- `/var/run/com.etchosts.hostshelper.sock` — helper Unix socket.

## Restoring a backup

Backups live in `/Library/Application Support/HostsHelper/backups/`. To restore
one:

```bash
sudo cp "/Library/Application Support/HostsHelper/backups/hosts-<timestamp>.bak" /etc/hosts
```

## License

Hosts is free and open source under the **GNU Affero General Public License v3.0**
(AGPLv3) — see [LICENSE](LICENSE). In short: you're free to use, study, modify,
and share it, but **any modified version you distribute or run as a network
service must also be released under the AGPLv3** (including its source). This is
what keeps the project open and prevents it from being turned into a closed
product.

**Commercial / dual licensing:** the copyright holder may offer Hosts under
separate commercial terms for anyone who can't comply with the AGPLv3. Contact
adityakar1998@gmail.com.

The name and logo are **trademarks** and are *not* covered by the AGPLv3 — see
[TRADEMARK.md](TRADEMARK.md). You can fork the code freely, but please rename your
fork and use your own icon.

## Contributing

Contributions are welcome. Hosts uses a Contributor License Agreement so it can
stay dual-licensable — see [CONTRIBUTING.md](CONTRIBUTING.md) and
[CLA.md](CLA.md) before opening a pull request.
