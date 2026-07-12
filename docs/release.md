# Releasing Hosts

Releases are produced with **Xcode's Archive → Organizer flow** (which handles
Developer ID signing, notarization, and stapling) plus a **Disk Utility DMG**,
and finished with a signed Sparkle appcast so existing installs auto-update.

Prerequisites (one-time):

- A **Developer ID Application** certificate in your login keychain (paid Apple
  Developer Program).
- Your Apple ID added under **Xcode → Settings → Accounts** so the Organizer can
  submit to Apple's notary service.
- The Sparkle **EdDSA private key** in your keychain (its public half is
  `SUPublicEDKey` in the app's Info.plist).

## 1. Bump the version

In Xcode, select the **etc-hosts** target → **General** and set:

- **Version** (`MARKETING_VERSION`) — e.g. `1.3.0`
- **Build** (`CURRENT_PROJECT_VERSION`) — same value, e.g. `1.3.0`

Sparkle compares `CFBundleVersion` to decide whether an update is newer, so the
Build value must increase with every release. Tag the commit `v1.3.0` to match.

## 2. Archive and export

1. **Product → Archive** (scheme `etc-hosts`, any-Mac/Release).
2. In the **Organizer**, select the archive → **Distribute App** → **Direct
   Distribution** (Developer ID). Xcode signs with your Developer ID cert,
   submits to the notary service, and staples the ticket.
3. When notarization completes, **Export** the notarized `HostsEditor.app`.

> **Do NOT pick "App Store Connect"** — Hosts cannot ship on the Mac App Store
> or TestFlight, and that path fails validation by design:
>
> - The App Store requires the **App Sandbox** on every executable, but a
>   sandboxed app cannot register a root `SMAppService` launch daemon, use the
>   `/var/run` helper socket, or write `/etc/hosts` — the app's core function.
> - **Sparkle self-updating is not allowed** in App Store builds (store apps
>   must update through the store), so the embedded Sparkle executables would
>   be rejected as well.
>
> Direct Distribution (Developer ID + notarization) is the only supported
> channel.

The exported app already contains the privileged helper
(`Contents/MacOS/com.etchosts.hostshelper`), its launchd plist
(`Contents/Library/LaunchDaemons/`), and the Sparkle framework — all re-signed
by the export.

## 3. Build the DMG

```bash
./scripts/create-dmg.sh <path/to/exported/HostsEditor.app>
```

The script reads the version from the app bundle and produces both release
assets in the repo root (gitignored):

- `HostsEditor-<version>.dmg` — the versioned download (referenced by the appcast).
- `HostsEditor.dmg` — a stable-named copy; the website's download button points
  at `releases/latest/download/HostsEditor.dmg`, so this must be on every release.

Because the app inside is notarized **and stapled**, Gatekeeper accepts it on
users' Macs. For belt-and-braces you can additionally sign — or sign, notarize,
and staple — the DMG itself:

```bash
./scripts/create-dmg.sh <path/to/HostsEditor.app> --sign      # codesign the DMG (.devid / DEVID_IDENTITY)
./scripts/create-dmg.sh <path/to/HostsEditor.app> --notarize  # + notarize & staple (NOTARY_PROFILE env)
```

<details>
<summary>Manual alternative (Disk Utility)</summary>

1. Make a staging folder containing the exported `HostsEditor.app` and an
   `/Applications` symlink (`ln -s /Applications Applications`) as the
   drag-and-drop target.
2. **Disk Utility → File → New Image → Image from Folder…**, pick the staging
   folder, format **compressed**, volume name **Hosts**.
3. Name the file `HostsEditor-<version>.dmg` and make the stable-named
   `HostsEditor.dmg` copy.

</details>

## 4. Generate the Sparkle appcast

```bash
./scripts/generate-appcast.sh HostsEditor-1.3.0.dmg 1.3.0
```

This signs the DMG with your EdDSA key, merges the previously published feed
(so older entries survive), and writes `appcast.xml`. **Without this step,
in-app updates will not see the new release.**

## 5. Publish the GitHub Release

Upload **all three** assets to a `v<version>` release:

```bash
gh release create v1.3.0 HostsEditor-1.3.0.dmg HostsEditor.dmg appcast.xml \
  --title "Hosts 1.3.0" --notes "See CHANGELOG.md"
```

- `HostsEditor-<version>.dmg` — the versioned download (referenced by the appcast).
- `HostsEditor.dmg` — stable name for the website's "latest" link.
- `appcast.xml` — the update feed (`SUFeedURL` points at
  `releases/latest/download/appcast.xml`).

## 6. Verify

```bash
spctl -a -vvv -t install HostsEditor-1.3.0.dmg   # Gatekeeper accepts
xcrun stapler validate HostsEditor-1.3.0.dmg      # ticket stapled (if you stapled the DMG)
```

Then install the **previous** version, open it, and confirm
**Check for Updates…** offers the new one.

## Releasing under your own developer account (forks)

The same flow works with any paid Apple Developer account — Xcode's Organizer
uses whatever team the targets are signed with, so first select **your** team
under **Signing & Capabilities** for both the `etc-hosts` and `HostsHelper`
targets (see [`build-from-source.md`](build-from-source.md) — a free account is
enough to build and run, but **Direct Distribution/notarization requires a paid
membership** with a Developer ID Application certificate).

The helper's app-trust check is team-relative, not hardcoded, so it works
unchanged under your team. If you distribute your own builds, also make them
update from **your** infrastructure, not this project's:

1. Generate your own Sparkle EdDSA key pair (`generate_keys`, in the same
   Sparkle tools bundle as `generate_appcast`) and put your public key in
   `etc-hosts/Info.plist` → `SUPublicEDKey`.
2. Point `SUFeedURL` in `etc-hosts/Info.plist` at your own appcast URL.
3. Update `REPO_URL` in `scripts/generate-appcast.sh` to your repository.
