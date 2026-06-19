# Build Hosts yourself with your own Apple signing identity

> **Interim install path.** Until Hosts ships as a signed, notarized download, you
> run it by building it from source and signing it with your **own free Apple
> signing certificate**. This takes about five minutes and needs only a free Apple
> ID — no paid Apple Developer Program membership.

## Why you sign it yourself

Hosts installs a small privileged `SMAppService` helper that writes `/etc/hosts`
as root, so the app never runs as root itself. macOS will only register that
helper if the app bundle is signed with a **real** (non-ad-hoc) certificate.

- A **free "Apple Development" certificate** — the kind Xcode creates from any
  Apple ID's "Personal Team" — is enough to build and run Hosts on your own Mac.
- Because you build it locally, **Gatekeeper doesn't block it**: there's no
  "unidentified developer" wall and nothing to notarize.
- A paid **Developer ID** certificate + notarization would only be needed to hand
  a prebuilt `.app` to *other* people who don't build it themselves. This project
  is distributed as source, so that isn't required — you build your own copy.

## Prerequisites

- macOS 13 (Ventura) or later.
- **Xcode** (free on the Mac App Store) — needed once to create your signing
  certificate. The Command Line Tools alone can compile the code, but Xcode is the
  simplest way to mint a development certificate into your keychain.
- An **Apple ID** (free; a paid developer account is *not* required).

## 1. Create your free signing certificate

1. Open **Xcode → Settings (⌘,) → Accounts**.
2. Click **+ → Apple ID** and sign in. Xcode creates a free **Personal Team** for
   your account.
3. Xcode usually provisions an **Apple Development** certificate automatically. If
   it doesn't, create any throwaway Xcode project, open **Signing & Capabilities**,
   choose your Personal Team, and let Xcode "Try Again" / provision — that writes
   the certificate into your **login keychain**. You can delete the project after.

## 2. Find your signing identity

```bash
security find-identity -v -p codesigning
```

Look for a line like:

```
  1) A1B2C3…  "Apple Development: you@example.com (TEAMID)"
```

Copy the quoted string — e.g. `Apple Development: you@example.com (TEAMID)`.

> **Heads-up:** `find-identity` sometimes prints `0 valid identities found` even
> when a usable Apple Development certificate exists in your keychain. If the build
> in step 4 signs successfully, you can ignore that message.

## 3. Point the build at your identity

`build.sh` resolves the signing identity in this order: the `SIGN_IDENTITY`
environment variable → a local `native/.signid` file → a placeholder. Pick one of
the first two:

**Option A — local file (recommended; set once, gitignored):**

```bash
echo 'Apple Development: you@example.com (TEAMID)' > native/.signid
```

**Option B — per build:**

```bash
SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" ./native/build.sh
```

`native/.signid` is git-ignored, so your identity never gets committed.

## 4. Build

```bash
cd native
./build.sh
```

This compiles the app and the privileged helper, assembles
`native/HostsEditor.app`, and signs both with your certificate and the hardened
runtime. On success you'll see `→ Signed & verified`.

## 5. Launch and approve the helper

```bash
open native/HostsEditor.app
```

On first launch the app registers its helper through `SMAppService`. The **first**
time, macOS leaves it pending and opens **System Settings → Login Items** — switch
**"Hosts"** on, return to the app, and unlock again to finish. There is **no
administrator-password prompt** for helper setup.

## Updating

Pull the latest source and re-run `./build.sh`. Your `native/.signid` persists, so
rebuilding is a single command.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `SMAppService` won't register / "operation not permitted" | Make sure you signed with a real identity, not ad-hoc (`-`). Re-check steps 2–3 and that `→ Signed & verified` printed. |
| `0 valid identities found` | Often a false negative — see the note in step 2. If the build still fails to sign, redo step 1 so a certificate exists. |
| `errSecInternalComponent` / missing **WWDR** certificate | Install the current Apple Worldwide Developer Relations intermediate certificate from Apple, then rebuild. |
| Certificate expired | Free development certificates are short-lived. Re-open Xcode (it renews automatically), then rebuild. |
| Helper enabled but editing stays disabled | Unlock the session again so the app enrolls its signing key with the freshly-approved helper. |

For how the helper, keys, and backups work — and how to fully remove them — see
[`helper.md`](helper.md).
