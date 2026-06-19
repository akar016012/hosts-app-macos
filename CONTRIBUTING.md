# Contributing

Thanks for your interest in improving Hosts. This guide covers how to build, run
tests, navigate the code, and how we name branches and commits.

## Building

```bash
cd native
./build.sh
```

The build compiles all app sources and the helper, bundles them, generates the
icon, and signs the result. It produces `native/HostsEditor.app` (a build
artifact — it is not tracked in git).

### Signing identity

`SMAppService` refuses to register an **ad-hoc–signed** daemon, so the bundle must
be signed with a real signing identity. A **free Apple Development certificate**
(from a free Apple ID "Personal Team" in Xcode) is enough to build and run
locally; a paid **Developer ID** + notarization is only needed to distribute to
other Macs (see [`docs/distribution.md`](docs/distribution.md)).

Override the identity used by the build with `SIGN_IDENTITY`:

```bash
SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" ./build.sh
```

The build uses a hardened runtime (`codesign --options runtime`).

## Running tests

```bash
bash native/test.sh
```

> Note: the test runner (`native/test.sh`) and its build directory
> (`native/.build-test/`) are being added; if the script is not yet present on
> your branch, pull the latest `main`. The test build directory is gitignored.

## Running the app

```bash
open native/HostsEditor.app
```

On first launch you'll be guided through onboarding (profile, theme, unlock
method) and asked to approve the helper in System Settings → Login Items. See
[`docs/helper.md`](docs/helper.md) for the helper lifecycle and an
uninstall/repair procedure.

## Code layout

- **`native/Core/`** — pure logic: hosts parsing and grouping, the data model,
  history, profile/PIN stores, the session signing key, the privileged-helper
  client, and the `SMAppService` lifecycle wrapper. No SwiftUI here.
- **`native/UI/`** — SwiftUI screens, sheets, row components, themes, button
  styles, and menu commands.
- **`native/HostsHelper.swift`** — the privileged root LaunchDaemon. It validates
  signed requests and is the only component that writes `/etc/hosts`.
- **`native/build.sh`** — the build/sign/bundle script.

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
