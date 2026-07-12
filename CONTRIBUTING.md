# Contributing

Thanks for your interest in improving Hosts. This guide covers how to build, run
tests, navigate the code, and how we name branches and commits.

## License & CLA (read first)

Hosts is licensed under the **AGPLv3** ([LICENSE](LICENSE)). By contributing you
agree to the **Contributor License Agreement** in [CLA.md](CLA.md), which lets the
maintainer keep the project dual-licensable (AGPLv3 + optional commercial terms).
You retain copyright to your work; the CLA just grants the maintainer a broad
license to it.

- First-time contributors: a CLA check will prompt you on your first pull request,
  or you can add your name to [`CONTRIBUTORS`](CONTRIBUTORS) as described in
  [CLA.md](CLA.md).
- New source files should start with the standard header:
  ```swift
  // SPDX-License-Identifier: AGPL-3.0-only
  // Copyright (C) 2026 Aditya Kar
  ```
- The app name and logo are trademarks ([TRADEMARK.md](TRADEMARK.md)); forks must
  rename and use their own icon.

## Building

Open `etc-hosts.xcodeproj` in Xcode and press **⌘B**, or from the command line:

```bash
xcodebuild -project etc-hosts.xcodeproj -scheme etc-hosts -configuration Debug build
```

The build compiles the app and the helper (two targets), embeds the helper and
its launchd plist into the bundle, pulls in Sparkle via Swift Package Manager,
and signs the result. It produces `HostsEditor.app` in DerivedData (a build
artifact — it is not tracked in git).

### Signing identity

`SMAppService` refuses to register an **ad-hoc–signed** daemon, so the bundle must
be signed with a real signing identity. A **free Apple Development certificate**
(from a free Apple ID "Personal Team" in Xcode) is enough to build and run
locally — select **your own team** under **Signing & Capabilities** for both
targets (they must match), or override it per build with
`xcodebuild … DEVELOPMENT_TEAM=YOURTEAMID build`. See
[`docs/build-from-source.md`](docs/build-from-source.md) for the full
walkthrough.

The build uses a hardened runtime.

## Running tests

```bash
bash scripts/test.sh
```

The runner compiles the suite with plain `swiftc` into `.build-test/`
(gitignored) and runs it in isolation. Add or update tests for any new logic in
`Core/`.

## Running the app

Run from Xcode (**⌘R**), or `open` the built `HostsEditor.app` from the products
directory.

On first launch you'll be guided through onboarding (profile, theme, unlock
method) and asked to approve the helper in System Settings → Login Items. See
[`docs/helper.md`](docs/helper.md) for the helper lifecycle and an
uninstall/repair procedure.

## Code layout

- **`etc-hosts/Core/`** — pure logic: hosts parsing and grouping, the data model,
  history, profile/PIN stores, the session signing key, the privileged-helper
  client, and the `SMAppService` lifecycle wrapper. No SwiftUI here.
- **`etc-hosts/UI/`** — SwiftUI screens, sheets, row components, themes, button
  styles, and menu commands.
- **`HostsHelper/main.swift`** — the privileged root LaunchDaemon (its own Xcode
  target). It validates signed requests and is the only component that writes
  `/etc/hosts`.
- **`etc-hosts.xcodeproj`** — the Xcode project that builds, bundles, and signs
  both targets.

Keep logic in `Core/` and presentation in `UI/`. Anything security-relevant
(signing, the helper protocol, write validation) deserves extra review — see
[`SECURITY.md`](SECURITY.md).

## Branches and commits

This repo follows a git-flow–style branching convention. Branch off `main`:

- `feature/<change-title>` for new features
- `fix/<change-title>` for bug fixes

Use [Conventional Commits](https://www.conventionalcommits.org/) for every commit
title (and body where useful), e.g.:

```
feat(profile): add profile picture support
fix(helper): reject reused nonces after restart
docs: document helper uninstall procedure
```

Common types: `feat`, `fix`, `docs`, `refactor`, `chore`, `test`.
