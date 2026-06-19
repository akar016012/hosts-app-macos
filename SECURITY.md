# Security Policy

This document describes the security architecture and threat model of Hosts, an
unprivileged macOS SwiftUI app that edits `/etc/hosts` through a privileged
LaunchDaemon helper, and explains how to report a vulnerability.

## Architecture

Hosts is split into two components with very different privilege levels:

- **The app** (`HostsEditor`) runs entirely as the logged-in user. It never runs
  as root. It parses, displays, and edits a working copy of the hosts file, then
  asks the helper to commit the result.
- **The helper** (`com.etchosts.hostshelper`) is a root LaunchDaemon bundled inside
  the app at `Contents/MacOS/com.etchosts.hostshelper`, with its launchd plist at
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
- **Peer code-signature requirement.** Before reading anything from a connection,
  the helper resolves the peer's audit token (`LOCAL_PEERTOKEN`), builds a
  `SecCode`, and requires it to satisfy a code requirement pinned to **this
  daemon's own Team Identifier**, the app's bundle identifier
  (`com.etchosts.hostseditor`), and Apple's anchor — i.e. the connecting process must
  actually be our signed app. This applies to the first `enroll` too, so an
  unrelated local process can neither plant the trust anchor nor drive writes even
  if it obtained the signing key. Root peers are exempt (already fully privileged);
  ad-hoc/unsigned dev builds, which `SMAppService` won't register anyway, fall back
  to the UID + signature gates because there is no team to pin against.
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
the app's code-signing identity, which for a locally-built app — rebuilt often
and signed with a short-lived free Apple Development certificate — is unstable
enough to force a keychain-password prompt on every signature. The file-based key
avoids that.

The consequence, stated honestly: the `0600` permission protects the key from
**other users** on the same Mac. A process running as the **same user** can still
read the key file — but on its own that is no longer enough to drive a write,
because the **peer code-signature requirement** (above) rejects any connector that
is not our signed app. To actually abuse a stolen key an attacker would have to
present our code identity as well: that means compromising or injecting into the
legitimate, hardened-runtime app process, not merely reading a file. The Touch ID
/ PIN gate is still only an app-session control and does not factor into this.

Residual risk: an attacker who can subvert the running signed app itself (code
injection, a malicious dynamic library where the runtime permits it, etc.) can
still issue writes. Further hardening — Secure Enclave–backed keys with a stable,
persistent code-signing identity rather than a short-lived per-developer
certificate — remains future work.

## Reporting a Vulnerability

If you believe you have found a security vulnerability in Hosts, please report it
privately by email to **adityakar1998@gmail.com**. Include:

- a description of the issue and its potential impact,
- steps to reproduce (a proof of concept if you have one), and
- any suggested remediation.

Please do **not** open a public issue for security reports. Allow a reasonable
amount of time for the issue to be investigated and fixed before any public
disclosure. Coordinated disclosure is appreciated.
