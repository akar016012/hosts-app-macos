#!/bin/bash
# Build a signed, notarized, stapled HostsEditor DMG for distribution to other
# Macs. Unlike build.sh (which targets a local, build-from-source install with a
# free Apple Development cert), this requires a paid Developer ID:
#
#   1. A "Developer ID Application" certificate in your login keychain.
#   2. A notarytool credential profile in your keychain (App Store Connect API
#      key or Apple ID + app-specific password), created once with:
#        xcrun notarytool store-credentials <profile> --key … --key-id … --issuer …
#
# Nothing secret lives in the repo: the signing identity is read from a
# gitignored native/.devid file (or the DEVID_IDENTITY env var), and the notary
# profile is referenced by name only (NOTARY_PROFILE env var; default below).
#
# Usage:
#   ./release.sh                 # version from latest git tag, identity from .devid
#   APP_VERSION=1.0.3 ./release.sh
#   DEVID_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=hosts-notary ./release.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="HostsEditor.app"
NOTARY_PROFILE="${NOTARY_PROFILE:-hosts-notary}"

fail() { echo "✗ $*" >&2; exit 1; }

# ── Resolve the release version ───────────────────────────────────────────────
# Prefer an explicit APP_VERSION; otherwise derive from the latest vX.Y.Z tag.
if [ -z "${APP_VERSION:-}" ]; then
  TAG="$(git -C .. describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
  [ -n "$TAG" ] || fail "No version: set APP_VERSION=… or create a vX.Y.Z git tag."
  APP_VERSION="${TAG#v}"
fi
export APP_VERSION
DMG="HostsEditor-${APP_VERSION}.dmg"

# ── Resolve the Developer ID signing identity ─────────────────────────────────
DEVID_IDENTITY="${DEVID_IDENTITY:-$( [ -f .devid ] && cat .devid || true )}"
[ -n "$DEVID_IDENTITY" ] || fail "No signing identity. Put your Developer ID in native/.devid, e.g.:
    echo 'Developer ID Application: Your Name (TEAMID)' > native/.devid
  (gitignored) — or pass DEVID_IDENTITY=… "

case "$DEVID_IDENTITY" in
  "Developer ID Application:"*) : ;;
  *) fail "Identity must be a 'Developer ID Application:' cert (got: $DEVID_IDENTITY).
  Apple Development certs cannot be notarized; only Developer ID can be distributed." ;;
esac

# ── Preflight: cert present? notary profile present? ──────────────────────────
security find-identity -v -p codesigning 2>/dev/null | grep -qF "$DEVID_IDENTITY" \
  || fail "Identity not found in keychain: $DEVID_IDENTITY
  Check:  security find-identity -v -p codesigning"

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || fail "Notary profile '$NOTARY_PROFILE' not usable. Create it once with:
    xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --key <AuthKey.p8> --key-id <ID> --issuer <ISSUER>
  or pass a different NOTARY_PROFILE=…"

echo "→ Release ${APP_VERSION}"
echo "  identity:  $DEVID_IDENTITY"
echo "  notary:    $NOTARY_PROFILE"
echo ""

# ── 1. Build + sign with the Developer ID (RELEASE=1 adds --timestamp) ────────
RELEASE=1 SIGN_IDENTITY="$DEVID_IDENTITY" APP_VERSION="$APP_VERSION" ./build.sh

# ── 2. Notarize the app, then staple the ticket onto it ───────────────────────
# Stapling the .app (not just the DMG) lets first launch succeed offline.
echo "→ Notarizing app (this can take a few minutes)…"
ZIP="HostsEditor-${APP_VERSION}.zip"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"

# ── 3. Build a compressed DMG with an /Applications drop target ───────────────
echo "→ Building ${DMG}…"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Hosts" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

# ── 4. Sign, notarize, and staple the DMG itself ──────────────────────────────
codesign --force --timestamp --sign "$DEVID_IDENTITY" "$DMG"
echo "→ Notarizing DMG…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

# A stable-named copy of the (already notarized + stapled) DMG so the website's
# /releases/latest/download/HostsEditor.dmg link auto-tracks the newest release
# without ever editing the site. The stapled ticket lives inside the file, so a
# plain copy stays valid. Upload BOTH to the GitHub Release.
STABLE_DMG="HostsEditor.dmg"
cp -f "$DMG" "$STABLE_DMG"

# ── 4b. Generate + sign the Sparkle appcast ───────────────────────────────────
# The app reads its update feed from this appcast, published as a GitHub Release
# asset at releases/latest/download/appcast.xml (auto-tracks the newest release,
# same trick as the stable DMG). generate_appcast signs each enclosure with the
# EdDSA private key in the keychain (public half is SUPublicEDKey in Info.plist)
# and records the version/length from the DMG's bundled Info.plist.
#
# We run it over a temp folder holding only THIS release's DMG plus the previously
# published appcast (downloaded if present), so prior entries are carried forward
# with their original version-specific URLs while the new entry gets this
# release's download prefix.
REPO_URL="https://github.com/akar016012/hosts-app-macos"
GEN_APPCAST="$(ls Vendor/Sparkle-*/bin/generate_appcast 2>/dev/null | head -1)"
[ -n "$GEN_APPCAST" ] || fail "generate_appcast not found under native/Vendor (build.sh fetches it)."
echo "→ Generating appcast…"
APPCAST_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING" "$APPCAST_DIR"' EXIT
cp "$DMG" "$APPCAST_DIR/"
curl -fsSL -o "$APPCAST_DIR/appcast.xml" \
  "$REPO_URL/releases/latest/download/appcast.xml" 2>/dev/null \
  && echo "  (merging into existing feed)" || echo "  (no existing feed — creating fresh)"
"$GEN_APPCAST" \
  --download-url-prefix "$REPO_URL/releases/download/v${APP_VERSION}/" \
  --link "$REPO_URL" \
  "$APPCAST_DIR"
cp -f "$APPCAST_DIR/appcast.xml" appcast.xml
echo "✓ $(pwd)/appcast.xml  — signed Sparkle feed."

# ── 5. Verify the way Gatekeeper will on the user's Mac ───────────────────────
echo "→ Verifying…"
spctl -a -vvv -t install "$DMG"
xcrun stapler validate "$DMG"

echo ""
echo "✓ $(pwd)/$DMG  — signed, notarized, stapled and ready to distribute."
echo "✓ $(pwd)/$STABLE_DMG  — stable-named copy for the website 'latest' download link."
echo "✓ $(pwd)/appcast.xml  — Sparkle update feed (must be on the Release for in-app updates)."
echo ""
echo "  Publish all three to a GitHub Release:"
echo "    gh release create v$APP_VERSION \"$DMG\" \"$STABLE_DMG\" appcast.xml \\"
echo "      --title \"Hosts $APP_VERSION\" --notes \"See CHANGELOG.md\""
echo "  (use 'gh release upload v$APP_VERSION ...' if the release already exists)"
