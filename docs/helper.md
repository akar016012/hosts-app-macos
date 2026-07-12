# The privileged helper: lifecycle, state, and uninstall

Hosts edits `/etc/hosts` through a small root LaunchDaemon called
`com.etchosts.hostshelper`. The app itself never runs as root; the helper is the
only privileged component, and it only writes the hosts file after verifying a
cryptographically signed request. This document covers how it installs, where it
keeps state, and how to remove or repair it. For the security rationale see
[`../SECURITY.md`](../SECURITY.md).

## Install and registration

- The helper executable ships **inside the app bundle** at
  `Contents/MacOS/com.etchosts.hostshelper`, with its launchd plist at
  `Contents/Library/LaunchDaemons/com.etchosts.hostshelper.plist`.
- It is registered and unregistered through **`SMAppService`** (macOS 13+) —
  there is no install script and no administrator-password prompt for setup.
- The **first** time the app prepares the helper, macOS leaves the registration
  **pending approval** and the app opens **System Settings → Login Items**. Enable
  "Hosts" there, then unlock again in the app to finish.
- After approval, the app **enrolls** its session signing public key with the
  helper over the helper's socket (trust on first use). Editing controls stay
  disabled until the helper is enabled **and** the current signing key is enrolled.
- On **every** connection (including the first enroll) the helper checks the peer's
  audit token and requires the connecting process to be the app itself — code-signed
  by the same Team Identifier as the helper, with the app's bundle id and Apple's
  anchor. A differently-signed binary is rejected before any request is read. This
  pins to the helper's *own* signing team, so any contributor's certificate works as
  long as the app and helper are built and signed together by Xcode.
- Because the helper lives in the bundle, **moving or deleting the app** effectively
  unregisters the daemon.

## Where state lives

**Helper state (root-owned, under `/Library/Application Support/HostsHelper/`):**

| Path | Purpose |
| --- | --- |
| `/Library/Application Support/HostsHelper/pubkey` | The app's public key trusted by the helper, recorded on first-use enrollment. |
| `/Library/Application Support/HostsHelper/uid` | The local user ID authorized to drive the helper. |
| `/Library/Application Support/HostsHelper/last-ts` | Highest accepted request timestamp; persists replay protection across restarts. |
| `/Library/Application Support/HostsHelper/backups/` | Timestamped `/etc/hosts` backups captured before each write (most recent 20 kept). |

**App state (user-owned, under `~/Library/Application Support/HostsEditor/`):**

| Path | Purpose |
| --- | --- |
| `~/Library/Application Support/HostsEditor/session-signing.key` | Owner-only (`0600`) private key used to sign write requests. |
| `~/Library/Application Support/HostsEditor/pin.json` | Salted, iterated PIN digest (the PIN itself is never stored). |
| `~/Library/Application Support/HostsEditor/pin-attempts.json` | PIN failure count and lockout deadline. |
| `~/Library/Application Support/HostsEditor/history.json` | In-app change history (recent snapshots). |

App preferences (onboarding state, profile, theme, default unlock method) live in
`~/Library/Preferences/com.etchosts.hostseditor.plist`.

**Runtime endpoints:**

- **Socket:** `/var/run/com.etchosts.hostshelper.sock` — the Unix domain socket the
  app uses to talk to the helper.
- **Log:** `/var/log/hostshelper.log` — the helper's standard-error log
  (`StandardErrorPath` in the launchd plist). Useful for diagnosing enrollment or
  write failures.

## Verifying the helper

```bash
# Is the daemon registered/enabled? (Also visible in System Settings → Login Items)
# The app shows this status; from the shell you can probe the socket and log:
ls -l /var/run/com.etchosts.hostshelper.sock
sudo tail -n 50 /var/log/hostshelper.log
```

The in-app "Hosts" menu also exposes a "Remove Privileged Helper…" item, and the
toggle in System Settings → Login Items enables/disables the daemon.

## Uninstall / repair

To fully remove the helper and force a clean re-enrollment on next launch:

1. **Unregister the daemon.** Use the app's **Hosts → Remove Privileged Helper…**
   menu item, or toggle "Hosts" off in **System Settings → Login Items**. (This is
   the `SMAppService` unregister path.) Quitting and deleting the app also
   unregisters it.

2. **Remove the helper's root-owned state:**

   ```bash
   sudo rm -rf "/Library/Application Support/HostsHelper"
   sudo rm -f /var/run/com.etchosts.hostshelper.sock
   ```

   > Back up `/Library/Application Support/HostsHelper/backups/` first if you want
   > to keep old `/etc/hosts` snapshots.

3. **Remove the app's user state** (optional — only if you want a fresh signing
   key, PIN, and history):

   ```bash
   rm -rf "$HOME/Library/Application Support/HostsEditor"
   ```

4. **Re-enroll.** Relaunch the app. It re-registers the helper (you'll approve it
   again in Login Items if needed) and enrolls a fresh signing public key on first
   unlock.

### Repair: signing key out of sync

If editing stays disabled because the helper's recorded key no longer matches the
app's key (for example after adding/removing Touch ID fingerprints, or after
deleting the signing key), reset the session key from the app's profile or lock
menu. The app generates a fresh key and re-enrolls it with the helper; you do
**not** need to remove the helper state for this case.
