# Security Policy

This document describes the security architecture and threat model of Hosts, an
unprivileged macOS SwiftUI app that edits `/etc/hosts` through a privileged
LaunchDaemon helper, and explains how to report a vulnerability.

## Architecture

Hosts is split into two components with very different privilege levels:

- **The app** (`HostsEditor`) runs entirely as the logged-in user. It never runs
  as root. It parses, displays, and edits a working copy of the hosts file, then
  asks the helper to commit the result.
- **The helper** (`com.aditya.hostshelper`) is a root LaunchDaemon bundled inside
  the app at `Contents/MacOS/com.aditya.hostshelper`, with its launchd plist at
  `Contents/Library/LaunchDaemons/`. It is registered and unregistered via
  `SMAppService` (macOS 13+) — there is no install script and no admin-password
  prompt for setup; the user approves it once in System Settings → Login Items.

The **only** privileged operation is the write to `/etc/hosts`. Everything else —
parsing, history, theming, profile, unlock — happens in the unprivileged app.
(The one remaining shell op, the optional DNS flush, uses a standard
administrator-password prompt and is not part of the helper trust path.)

## Trust model

The helper does not trust the app because of who is talking to it; it trusts a
**cryptographic signature**.

- **Signed write requests.** Each write is an ECDSA P-256 (X9.62 / SHA-256)
  signature over a canonical message: `hostshelper-v1\n<ts>\n<nonce>\n<contentBase64>`.
  The signing private key never leaves the app; the helper only ever sees the
  public key and signatures.
- **Trust on first use (TOFU) enrollment.** With `SMAppService` there is no root
  install script to plant the trusted key. Instead the helper accepts a single
  `enroll` message from an authorized peer and records the app's public key
  **root-owned** at `/Library/Application Support/HostsHelper/pubkey`. After that,
  it only re-enrolls (rotates the key) for that same authorized user, so an
  unrelated local user cannot swap the trust anchor.
- **Authorized UID + peer check (defense in depth).** The first local connector
  to enroll becomes the authorized UID, recorded root-owned at
  `/Library/Application Support/HostsHelper/uid`. The socket is world-connectable
  for compatibility, so the helper uses `getpeereid()` to reject connections from
  any user other than the authorized UID (or root) before processing a request.
  The signature remains the real gate; the peer check is an extra layer.
- **Replay protection.** Requests carry a timestamp and a nonce. The helper
  rejects requests outside a tight clock window (30s lead / 90s lag), rejects
  timestamps older than the last accepted one, and rejects reused nonces. The
  highest accepted timestamp is persisted root-owned
  (`/Library/Application Support/HostsHelper/last-ts`) so replay protection
  survives a daemon restart or reboot; the in-memory nonce set is a bounded FIFO.
- **Safe write.** Writes go to a fresh temp file in the same directory opened with
  `O_NOFOLLOW | O_EXCL` (so an attacker-planted symlink cannot redirect the
  write), then `rename()` atomically swaps it over `/etc/hosts` and ownership is
  reset to `root:wheel`. Input is bounded to **8 MB** and rejected if it contains
  control characters that have no business in a hosts file.
- **Automatic backups.** Before each write the helper copies the current
  `/etc/hosts` to a timestamped file under
  `/Library/Application Support/HostsHelper/backups/`, keeping the most recent 20.

## Session unlock

Editing is gated behind a per-session unlock, by either:

- **Touch ID**, when available and enrolled; or
- **A PIN**, stored only as a random-salted, 250,000-iteration SHA-256 digest in
  an owner-only (`0600`) file. The PIN itself is never stored. Verification is a
  constant-time compare, and wrong attempts trigger a persisted lockout with
  escalating backoff (starting at 30s, doubling, capped at 1 hour).

Important: **Touch ID and the PIN are app-level gates** on whether the session is
unlocked. They are a usability and local-presence control, not the cryptographic
authorization. The real authorization for a privileged write is possession of the
**session signing private key** — the helper verifies signatures, not unlock
state.

## Known limitation

The session signing private key is stored as a `0600` file in the user's
Application Support directory
(`~/Library/Application Support/HostsEditor/session-signing.key`), not in the
keychain. This is a deliberate trade-off: a keychain-stored key binds an ACL to
the app's code signature, which for an ad-hoc / frequently-rebuilt app changes on
every build and forces a keychain-password prompt on every signature. The
file-based key avoids that.

The consequence, stated honestly: the `0600` permission protects the key from
**other users** on the same Mac, but it does **not** protect it from malware or a
compromised process running as the **same user**. Any process running as you can
read the key file and, in principle, forge valid write requests to the helper —
which only means it could edit `/etc/hosts`, the same thing any process running
as you could attempt by other means. The Touch ID / PIN gate does not mitigate
this, because it gates the app session, not access to the key file. Hardening
this (e.g. Secure Enclave–backed keys with a stable signing identity) is future
work and requires a non-ad-hoc, stable code signature.

## Reporting a Vulnerability

If you believe you have found a security vulnerability in Hosts, please report it
privately by email to **adityakar1998@gmail.com**. Include:

- a description of the issue and its potential impact,
- steps to reproduce (a proof of concept if you have one), and
- any suggested remediation.

Please do **not** open a public issue for security reports. Allow a reasonable
amount of time for the issue to be investigated and fixed before any public
disclosure. Coordinated disclosure is appreciated.
