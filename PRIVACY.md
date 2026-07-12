# Privacy Policy

**Last updated: 2026-06-30**

Hosts is a native macOS application that edits `/etc/hosts` on your Mac.
**The app does not collect, transmit, or share any personal data.** All
information the app stores stays on your Mac under your control.

This document describes every piece of data the app stores, where it is stored,
and how to delete it.

## Data stored on your Mac

### Application data (user-owned, `~/Library/`)

| What | Where | Purpose |
|------|-------|---------|
| App preferences | `~/Library/Preferences/com.etchosts.hostseditor.plist` | Onboarding completion, local profile name/email, selected theme, custom theme data, unlock method preference |
| Change history | `~/Library/Application Support/HostsEditor/history.json` | In-app history of edits, capped at 50 snapshots; used for one-click revert |
| PIN digest | `~/Library/Application Support/HostsEditor/pin.json` | Salted PBKDF2-HMAC-SHA256 digest of your optional app PIN. The PIN itself is never stored. |
| Session signing key | `~/Library/Application Support/HostsEditor/session-signing.key` | ECDSA P-256 private key used to sign write requests to the privileged helper. Owner-only (`0600`). Never leaves your Mac. |

### Helper data (root-owned, `/Library/`)

The privileged helper runs as root and stores a small amount of trust state:

| What | Where | Purpose |
|------|-------|---------|
| Trusted public key | `/Library/Application Support/HostsHelper/pubkey` | The app's public key, recorded on first enrollment, so the helper can verify signed write requests |
| Authorized user ID | `/Library/Application Support/HostsHelper/uid` | The local macOS user allowed to drive the helper |
| Automatic backups | `/Library/Application Support/HostsHelper/backups/` | Timestamped copies of `/etc/hosts` captured before each write; kept for 20 most recent |
| Replay protection | `/Library/Application Support/HostsHelper/last-ts` | Highest accepted write-request timestamp, persisted so replay protection survives reboots |

### The file being edited

`/etc/hosts` — the system hosts file. The app reads and writes this file via
the privileged helper. Disabled entries are stored as commented-out lines within
this file.

## What is NOT collected

- No analytics, telemetry, crash reports, or usage data.
- No network requests are made by the app itself during normal operation.
- No data is synced to any cloud service.
- Your profile name and email (entered during onboarding) are stored only in the
  local macOS preferences plist and are never transmitted anywhere.

## Update checks (Sparkle)

The distributed binary uses [Sparkle](https://sparkle-project.org/) for
automatic update checks. When update checking is enabled (the default), Sparkle
periodically contacts the project's update feed URL to check for a newer
version. This request includes the current app version and macOS version. No
personal information is included. You can disable update checks in
**Settings → General**. Update checking is not part of the open-source code;
builds compiled from source do not include a Sparkle configuration and make no
network requests.

## How to delete all app data

To completely remove all data stored by Hosts:

1. **Unregister and remove the helper** — open the app, choose
   **Hosts → Remove Privileged Helper…**, then confirm. Or toggle the app off in
   **System Settings → General → Login Items & Extensions**.

2. **Delete user data:**

   ```bash
   rm ~/Library/Preferences/com.etchosts.hostseditor.plist
   rm -rf ~/Library/Application\ Support/HostsEditor/
   ```

3. **Delete helper data (requires administrator password):**

   ```bash
   sudo rm -rf /Library/Application\ Support/HostsHelper/
   ```

4. **Delete the app** — drag `HostsEditor.app` from `/Applications` to the Trash.

After step 1, the helper executable and its launchd plist (bundled inside the
app) are automatically unregistered from `SMAppService`.

## Contact

If you have questions about this policy, contact the maintainer at
[adityakar1998@gmail.com](mailto:adityakar1998@gmail.com).
