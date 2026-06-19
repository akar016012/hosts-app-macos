# Hosts — SwiftUI `/etc/hosts` editor

A native macOS SwiftUI app for viewing and editing `/etc/hosts`: add, edit,
enable/disable, delete entries, search/filter, edit the raw file, and flush the
macOS DNS cache.

## Features

- **Toggle entries on/off** without deleting them (comments the line out).
- **Add / edit / delete** entries with IP + hostname validation.
- **Search & filter** by IP, hostname, or comment; filter by active/disabled.
- **Raw editor** for direct edits to the whole file.
- **Touch ID session unlock** for edits through a privileged helper.
- **Automatic backups** — a timestamped copy is saved before every write.
- **Flush DNS** button (macOS).
- No web server, browser UI, Node.js, or npm dependencies.

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

The app asks for Touch ID when it launches. After that, edits stay unlocked for
the rest of that app session and do not ask for your fingerprint again.

During launch/setup, the app may also install or refresh a privileged helper
with the native macOS administrator prompt. Editing controls stay disabled until
this setup is complete, and edits do not trigger helper installation prompts.

Touch ID must be available and enrolled on the Mac. If you add or remove
fingerprints in System Settings, click the Touch ID control in the app to reset
approvals and create a fresh session signing key.

## How it works

- `native/HostsEditor.swift` — the SwiftUI app entry point.
- `native/Core/` — app state, parsing, host grouping, Touch ID session signing,
  and privileged-helper communication.
- `native/UI/` — SwiftUI screens, sheets, row components, themes, and button
  styles.
- `native/HostsHelper.swift` — the privileged LaunchDaemon helper. It only
  writes `/etc/hosts` after validating a request signed by the app's Secure
  session key.
- `native/build.sh` — compiles all app sources and the helper, bundles them,
  generates the icon, and ad-hoc signs the app bundle.

Disabled entries are stored as commented-out lines.

## Restoring a backup

Backups live in `/Library/Application Support/HostsHelper/backups/`. To restore
one:

```bash
sudo cp "/Library/Application Support/HostsHelper/backups/hosts-<timestamp>.bak" /etc/hosts
```
