# Build Hosts yourself with your own Apple signing identity

> **Optional — building from source is an alternative to the download.** Hosts now
> ships as a [signed, notarized `.dmg`](https://etc-hosts.com/#install) you can
> drag-and-drop install with no build step. This guide is for people who'd rather build
> it themselves and sign it with their **own free Apple signing certificate** — it
> takes about five minutes and needs only a free Apple ID, no paid Apple Developer
> Program membership.

## Why you sign it yourself

Hosts installs a small privileged `SMAppService` helper that writes `/etc/hosts`
as root, so the app never runs as root itself. macOS will only register that
helper if the app bundle is signed with a **real** (non-ad-hoc) certificate.

- A **free "Apple Development" certificate** — the kind Xcode creates from any
  Apple ID's "Personal Team" — is enough to build and run Hosts on your own Mac.
- Because you build it locally, **Gatekeeper doesn't block it**: there's no
  "unidentified developer" wall and nothing to notarize.
- A paid **Developer ID** certificate + notarization is what produces the prebuilt
  `.dmg` download for *other* people (via Xcode's Archive → Organizer flow — see
  [`release.md`](release.md)). Building your own copy from source doesn't
  require it.

## Prerequisites

- macOS 13 (Ventura) or later.
- **Xcode** (free on the Mac App Store) — the project is a standard Xcode project
  (`etc-hosts.xcodeproj`) with two targets: the app and its privileged helper.
- An **Apple ID** (free; a paid developer account is *not* required).

## 1. Create your free signing certificate

1. Open **Xcode → Settings (⌘,) → Accounts**.
2. Click **+ → Apple ID** and sign in. Xcode creates a free **Personal Team** for
   your account.
3. Xcode usually provisions an **Apple Development** certificate automatically.

## 2. Point the project at your own team

The project file ships with the maintainer's team selected, so the one change
you need is swapping in **your** team — any Apple Developer account works,
including a free Personal Team:

1. Open `etc-hosts.xcodeproj` in Xcode.
2. Select the project in the navigator, then the **etc-hosts** target →
   **Signing & Capabilities**.
3. Under **Team**, pick your own team (e.g. "Your Name (Personal Team)").
4. Repeat for the **HostsHelper** target — it must use the **same team**.

Signing is set to **Automatic**, so Xcode picks (or provisions) your Apple
Development certificate itself; you can keep the bundle identifiers as they are.

> Both targets must be signed by the **same team** — the helper checks, at
> runtime, that the app connecting to it is signed by the team the helper
> itself was built with. Mismatched teams mean the helper refuses every request.

## 3. Build

Either press **⌘R** in Xcode (scheme `etc-hosts`), or from the command line:

```bash
xcodebuild -project etc-hosts.xcodeproj -scheme etc-hosts -configuration Debug build
```

If you'd rather not edit the project file at all, override the team for both
targets on the command line (find your ten-character Team ID in Xcode →
Settings → Accounts, or at developer.apple.com/account under Membership):

```bash
xcodebuild -project etc-hosts.xcodeproj -scheme etc-hosts -configuration Debug \
  DEVELOPMENT_TEAM=YOURTEAMID build
```

This compiles the app and the privileged helper, embeds the helper and its
launchd plist into `HostsEditor.app`, pulls in the Sparkle framework via Swift
Package Manager, and signs everything with your certificate and the hardened
runtime.

## 4. Launch and approve the helper

Run the app from Xcode, or `open` the built `HostsEditor.app` from Xcode's
Products directory.

On first launch the app registers its helper through `SMAppService`. The **first**
time, macOS leaves it pending and opens **System Settings → Login Items** — switch
**"Hosts"** on, return to the app, and unlock again to finish. There is **no
administrator-password prompt** for helper setup.

## Updating

Pull the latest source and rebuild (⌘R). Your team selection persists.

## Running the tests

The pure-logic Core sources have a standalone test suite that compiles directly
with `swiftc`:

```bash
./scripts/test.sh
```

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `SMAppService` won't register / "operation not permitted" | Make sure both targets are signed with a real identity, not ad-hoc. Re-check step 2. |
| `0 valid identities found` from `security find-identity` | Often a false negative. If Xcode builds and signs successfully, ignore it. |
| `errSecInternalComponent` / missing **WWDR** certificate | Install the current Apple Worldwide Developer Relations intermediate certificate from Apple, then rebuild. |
| Certificate expired | Free development certificates are short-lived. Re-open Xcode (it renews automatically), then rebuild. |
| Helper enabled but editing stays disabled | Unlock the session again so the app enrolls its signing key with the freshly-approved helper. |

For how the helper, keys, and backups work — and how to fully remove them — see
[`helper.md`](helper.md).
