#!/bin/bash
# Generate + sign the Sparkle appcast for a release DMG.
#
# The app reads its update feed from appcast.xml, published as a GitHub Release
# asset at releases/latest/download/appcast.xml. Run this AFTER you've produced
# the final (signed, notarized) DMG for a release, then upload the resulting
# appcast.xml alongside the DMG on the GitHub Release.
#
# generate_appcast signs each enclosure with the EdDSA private key in your
# keychain (the public half is SUPublicEDKey in the app's Info.plist) and reads
# the version from the DMG's bundled Info.plist — so the app inside the DMG must
# already carry the release version.
#
# Usage:
#   ./scripts/generate-appcast.sh HostsEditor-1.3.0.dmg 1.3.0
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "✗ $*" >&2; exit 1; }

DMG="${1:-}"; APP_VERSION="${2:-}"
[ -n "$DMG" ] && [ -n "$APP_VERSION" ] || fail "Usage: ./scripts/generate-appcast.sh <release.dmg> <version>   e.g. ./scripts/generate-appcast.sh HostsEditor-1.3.0.dmg 1.3.0"
[ -f "$DMG" ] || fail "DMG not found: $DMG"

REPO_URL="https://github.com/akar016012/hosts-app-macos"

# generate_appcast ships with Sparkle. Prefer the copy inside the SPM artifact
# checkout in DerivedData (put there when Xcode resolved the Sparkle package);
# fall back to downloading the pinned, checksum-verified release tools into a
# gitignored .tools/ dir.
SPARKLE_VERSION="2.9.3"
SPARKLE_SHA256="74a07da821f92b79310009954c0e15f350173374a3abe39095b4fc5096916be6"
GEN_APPCAST="$(find ~/Library/Developer/Xcode/DerivedData -type f -path '*artifacts*parkle*/bin/generate_appcast' 2>/dev/null | head -1)"
if [ -z "$GEN_APPCAST" ]; then
  GEN_APPCAST=".tools/Sparkle-${SPARKLE_VERSION}/bin/generate_appcast"
  if [ ! -x "$GEN_APPCAST" ]; then
    echo "→ Fetching Sparkle ${SPARKLE_VERSION} tools…"
    mkdir -p ".tools/Sparkle-${SPARKLE_VERSION}"
    TARBALL=".tools/Sparkle-${SPARKLE_VERSION}.tar.xz"
    curl -fL --retry 3 -o "$TARBALL" \
      "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
    echo "$SPARKLE_SHA256  $TARBALL" | shasum -a 256 -c - \
      || fail "Sparkle checksum mismatch — refusing to continue."
    tar -xJf "$TARBALL" -C ".tools/Sparkle-${SPARKLE_VERSION}"
  fi
fi
[ -x "$GEN_APPCAST" ] || fail "generate_appcast not found."

# Run it over a temp folder holding only THIS release's DMG plus the previously
# published appcast (downloaded if present), so prior entries are carried forward
# with their original version-specific URLs while the new entry gets this
# release's download prefix.
echo "→ Generating appcast…"
APPCAST_DIR="$(mktemp -d)"
trap 'rm -rf "$APPCAST_DIR"' EXIT
cp "$DMG" "$APPCAST_DIR/"
curl -fsSL -o "$APPCAST_DIR/appcast.xml" \
  "$REPO_URL/releases/latest/download/appcast.xml" 2>/dev/null \
  && echo "  (merging into existing feed)" || echo "  (no existing feed — creating fresh)"
"$GEN_APPCAST" \
  --download-url-prefix "$REPO_URL/releases/download/v${APP_VERSION}/" \
  --link "$REPO_URL" \
  "$APPCAST_DIR"
cp -f "$APPCAST_DIR/appcast.xml" appcast.xml
echo "✓ $(pwd)/appcast.xml  — signed Sparkle feed. Upload it to the GitHub Release."
