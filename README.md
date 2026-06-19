# Hosts — SwiftUI `/etc/hosts` editor

A native macOS SwiftUI app for viewing and editing `/etc/hosts`: add, edit,
enable/disable, delete entries, search/filter, edit the raw file, and flush the
macOS DNS cache.

## Features

- **Toggle entries on/off** without deleting them (comments the line out).
- **Add / edit / delete** entries with IP + hostname validation.
- **Search & filter** by IP, hostname, or comment; filter by active/disabled.
- **Duplicate detection** — flags hostnames that map to more than one IP.
- **Import / export** an entire hosts file (File menu).
- **Raw editor** for direct edits to the whole file.
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
| Raw file / History | ⌘R / ⌘Y |
| Undo last change | ⌥⌘Z |
| Flush DNS cache | ⌘K |
| Settings | ⌘, |

## Build

```bash
cd native
./build.sh
```

The build creates `native/HostsEditor.app`.

## Run

Open the app from Finder, or run:

```bash
open native/HostsEditor.app
```

On first launch, the app shows a welcome tour where you can set a local profile,
pick a theme, and choose how edits unlock. Returning users unlock the edit
session with Touch ID or an app PIN; edits stay unlocked for the rest of that
app session.

During launch/setup, the app may also install or refresh a privileged helper
with the native macOS administrator prompt. Editing controls stay disabled until
this setup is complete, and edits do not trigger helper installation prompts.

Touch ID must be available and enrolled on the Mac for Touch ID unlock. If you
add or remove fingerprints in System Settings, reset the session key from the
profile or lock menu so the helper receives the fresh public key.

## How it works

- `native/HostsEditor.swift` — the SwiftUI app entry point.
- `native/Core/` — app state, parsing, host grouping, session signing, local
  history, and privileged-helper communication.
- `native/UI/` — SwiftUI screens, sheets, row components, themes, and button
  styles.
- `native/HostsHelper.swift` — the privileged LaunchDaemon helper. It only
  writes `/etc/hosts` after validating a request signed by the app's session
  key.
- `native/build.sh` — compiles all app sources and the helper, bundles them,
  generates the icon, and ad-hoc signs the app bundle.

Disabled entries are stored as commented-out lines.

## Stored data and config

The app intentionally keeps runtime state in standard macOS locations:

- `/etc/hosts` — the file being edited. Disabled entries are commented out in
  this file.
- `~/Library/Preferences/com.aditya.hostseditor.plist` — `UserDefaults` values,
  including onboarding completion, local profile name/email, selected theme,
  custom theme data, and the default unlock method.
- `~/Library/Application Support/HostsEditor/history.json` — in-app change
  history, capped at the most recent 50 snapshots.
- `~/Library/Application Support/HostsEditor/pin.json` — salted, iterated PIN
  digest for PIN unlock. The PIN itself is never stored.
- `~/Library/Application Support/HostsEditor/session-signing.key` — owner-only
  private key used to sign write requests sent to the privileged helper.

The privileged helper also keeps root-owned install and trust state:

- `/Library/PrivilegedHelperTools/com.aditya.hostshelper` — installed helper
  executable.
- `/Library/LaunchDaemons/com.aditya.hostshelper.plist` — LaunchDaemon plist.
- `/Library/Application Support/HostsHelper/pubkey` — public key trusted by the
  helper.
- `/Library/Application Support/HostsHelper/uid` — local user ID allowed to
  drive the helper.
- `/Library/Application Support/HostsHelper/backups/` — timestamped backups
  captured before each write.
- `/var/run/com.aditya.hostshelper.sock` — helper Unix socket.

## Restoring a backup

Backups live in `/Library/Application Support/HostsHelper/backups/`. To restore
one:

```bash
sudo cp "/Library/Application Support/HostsHelper/backups/hosts-<timestamp>.bak" /etc/hosts
```
