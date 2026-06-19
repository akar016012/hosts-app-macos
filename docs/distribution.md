# Distribution plan: Developer ID signing, notarization, packaging

This is a **checklist/plan** for distributing Hosts to other Macs (including paid
distribution). It is **not done yet** — most steps require a **paid Apple
Developer Program** account. Steps that depend on your Apple credentials, Team ID,
or app-specific passwords are marked **(credential-dependent)**.

For local development you only need a free Apple Development certificate — see
[`../CONTRIBUTING.md`](../CONTRIBUTING.md). This document covers what changes when
you ship to machines you don't control.

## Why the current build isn't distributable

`native/build.sh` already signs with a hardened runtime
(`codesign --options runtime`), which is a prerequisite for notarization. But it
signs with an **Apple Development** certificate. Apps distributed outside the Mac
App Store must be signed with a **Developer ID Application** certificate and then
**notarized** by Apple, or Gatekeeper will block them on first launch.

## Checklist

### 1. Apple Developer account and certificates (credential-dependent)

- [ ] Enroll in the paid Apple Developer Program.
- [ ] Create a **Developer ID Application** certificate (and, if shipping a
      `.pkg`, a **Developer ID Installer** certificate) in the Apple Developer
      portal or via Xcode → Settings → Accounts → Manage Certificates.
- [ ] Confirm it appears locally:

  ```bash
  security find-identity -v -p codesigning
  ```

  Look for `Developer ID Application: Your Name (TEAMID)`.

### 2. Sign with Developer ID (hardened runtime)

The build already uses `--options runtime`. Point it at the Developer ID identity:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

- [ ] Verify the signature and that the runtime is hardened:

  ```bash
  codesign --verify --deep --strict --verbose=2 native/HostsEditor.app
  codesign -d --entitlements - native/HostsEditor.app
  ```

> The bundled helper is signed with a pinned identifier
> (`--identifier com.aditya.hostshelper`); keep that when switching identities so
> `SMAppService` registration keeps working.

### 3. Notarize with `notarytool` (credential-dependent)

Notarization runs on a zipped (or packaged) build, not the raw `.app`.

- [ ] Store credentials once in the keychain (uses an **app-specific password**
      from appleid.apple.com):

  ```bash
  xcrun notarytool store-credentials "HostsNotary" \
    --apple-id "you@example.com" \
    --team-id "TEAMID" \
    --password "app-specific-password"
  ```

- [ ] Zip and submit, waiting for the result:

  ```bash
  ditto -c -k --keepParent native/HostsEditor.app HostsEditor.zip
  xcrun notarytool submit HostsEditor.zip --keychain-profile "HostsNotary" --wait
  ```

- [ ] If it fails, pull the log:

  ```bash
  xcrun notarytool log <submission-id> --keychain-profile "HostsNotary"
  ```

### 4. Staple the ticket

So the app validates offline after notarization:

```bash
xcrun stapler staple native/HostsEditor.app
xcrun stapler validate native/HostsEditor.app
spctl -a -vvv -t install native/HostsEditor.app   # Gatekeeper assessment
```

### 5. Package a versioned artifact

Pick one (and keep the version in sync with `CFBundleShortVersionString` in
`native/build.sh` and the entry in [`../CHANGELOG.md`](../CHANGELOG.md)):

- **DMG**
  ```bash
  hdiutil create -volname "Hosts" -srcfolder native/HostsEditor.app \
    -ov -format UDZO "Hosts-1.0.0.dmg"
  ```
  Then sign + notarize + staple the `.dmg` itself (same `notarytool` /
  `stapler` flow as above).

- **PKG** (credential-dependent: needs Developer ID Installer)
  ```bash
  productbuild --component native/HostsEditor.app /Applications \
    --sign "Developer ID Installer: Your Name (TEAMID)" "Hosts-1.0.0.pkg"
  ```
  Then notarize + staple the `.pkg`.

- [ ] Notarize and staple the chosen artifact, not just the inner `.app`.

### 6. Auto-update path (Sparkle-style)

For shipping updates without the Mac App Store, plan a **Sparkle** integration:

- [ ] Add the Sparkle framework to the app bundle and embed it in the build.
- [ ] Generate an **EdDSA (Ed25519) update-signing key pair** with Sparkle's
      `generate_keys` tool; keep the private key offline (credential-dependent).
- [ ] Host an `appcast.xml` feed; each item points at a notarized, stapled
      `.dmg`/`.zip` and includes the Sparkle EdDSA signature
      (`sign_update`) and length.
- [ ] Set `SUFeedURL` and the public EdDSA key in `Info.plist`.
- [ ] On each release: bump the version, build → sign → notarize → staple →
      sign the update with `sign_update` → publish the appcast entry.

## Release checklist (each version)

1. [ ] Bump `CFBundleShortVersionString` / `CFBundleVersion` in `native/build.sh`.
2. [ ] Move the `[Unreleased]` notes to a new version section in `CHANGELOG.md`.
3. [ ] Build with the Developer ID identity.
4. [ ] Notarize and staple.
5. [ ] Package the versioned `.dmg`/`.pkg`.
6. [ ] (If using Sparkle) sign the update and update the appcast.
7. [ ] Tag the release in git.
