<!--
Thanks for contributing to Hosts! Please fill out the sections below and tick the
checklist. The CLA bot will ask you to sign on this PR if you haven't already.
-->

## Summary

<!-- What does this change, and why? -->

## Related issues

<!-- e.g. Closes #123 -->

## Checklist

- [ ] I have read and agree to the [Contributor License Agreement](https://github.com/akar016012/hosts-app-macos/blob/main/CLA.md). (The CLA bot will prompt me to sign on this PR if I haven't.)
- [ ] The app builds: `xcodebuild -project etc-hosts.xcodeproj -scheme etc-hosts -configuration Debug build` (or ⌘B in Xcode).
- [ ] Tests pass: `bash scripts/test.sh` — and I added/updated tests for any new logic.
- [ ] Any new source file starts with the SPDX header:
      `// SPDX-License-Identifier: AGPL-3.0-only`
- [ ] Commits follow [Conventional Commits](https://www.conventionalcommits.org/) and my branch is named `feature/<title>` or `fix/<title>`.
- [ ] I did **not** commit secrets, personal signing identities, or generated build artifacts (`build/`, `.signid`, `.devid`).
