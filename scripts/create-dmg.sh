#!/bin/bash
# Package an exported HostsEditor.app into the release DMG.
#
# Creates a compressed disk image with an /Applications drop target:
#   HostsEditor-<version>.dmg   — the versioned release asset (referenced by the appcast)
#   HostsEditor.dmg             — stable-named copy for the website's "latest" download link
#
# The version is read from the app bundle's Info.plist, so archive/export with
# the release version set first (see docs/release.md). The app should be the
# notarized, stapled export from Xcode's Organizer — the DMG inherits its
# Gatekeeper acceptance from the stapled app inside.
#
# Usage:
#   ./scripts/create-dmg.sh <path/to/HostsEditor.app>              # DMG only
#   ./scripts/create-dmg.sh <path/to/HostsEditor.app> --sign      # + codesign the DMG (.devid / DEVID_IDENTITY)
#   ./scripts/create-dmg.sh <path/to/HostsEditor.app> --notarize  # + notarize & staple the DMG too
#                                                                  #   (implies --sign; NOTARY_PROFILE env, default hosts-notary)
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "✗ $*" >&2; exit 1; }

APP="${1:-}"
[ -n "$APP" ] || fail "Usage: ./scripts/create-dmg.sh <path/to/HostsEditor.app> [--sign|--notarize]"
[ -d "$APP" ] || fail "App not found: $APP"

SIGN=0; NOTARIZE=0
case "${2:-}" in
  "") : ;;
  --sign) SIGN=1 ;;
  --notarize) SIGN=1; NOTARIZE=1 ;;
  *) fail "Unknown option: $2 (expected --sign or --notarize)" ;;
esac

# ── Read the release version from the app bundle ──────────────────────────────
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true)"
[ -n "$APP_VERSION" ] || fail "Could not read CFBundleShortVersionString from $APP"
DMG="HostsEditor-${APP_VERSION}.dmg"
STABLE_DMG="HostsEditor.dmg"
echo "→ Packaging ${APP} (version ${APP_VERSION})"

# ── Resolve signing bits up front so we fail before doing any work ────────────
if [ "$SIGN" = 1 ]; then
  DEVID_IDENTITY="${DEVID_IDENTITY:-$( [ -f .devid ] && cat .devid || true )}"
  [ -n "$DEVID_IDENTITY" ] || fail "No signing identity. Put your Developer ID in .devid or pass DEVID_IDENTITY=…"
  security find-identity -v -p codesigning 2>/dev/null | grep -qF "$DEVID_IDENTITY" \
    || fail "Identity not found in keychain: $DEVID_IDENTITY"
fi
if [ "$NOTARIZE" = 1 ]; then
  NOTARY_PROFILE="${NOTARY_PROFILE:-hosts-notary}"
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || fail "Notary profile '$NOTARY_PROFILE' not usable. Create it once with:
    xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --key <AuthKey.p8> --key-id <ID> --issuer <ISSUER>"
fi

# ── Build the DMG with an /Applications drop target ───────────────────────────
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Hosts" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
echo "✓ $(pwd)/$DMG"

# ── Optionally sign / notarize / staple the DMG itself ────────────────────────
if [ "$SIGN" = 1 ]; then
  codesign --force --timestamp --sign "$DEVID_IDENTITY" "$DMG"
  echo "✓ DMG signed ($DEVID_IDENTITY)"
fi
if [ "$NOTARIZE" = 1 ]; then
  echo "→ Notarizing DMG (this can take a few minutes)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  echo "→ Verifying…"
  spctl -a -vvv -t install "$DMG"
  xcrun stapler validate "$DMG"
fi

cp -f "$DMG" "$STABLE_DMG"
echo "✓ $(pwd)/$STABLE_DMG  — stable-named copy for the website 'latest' download link."
echo ""
echo "  Next: ./scripts/generate-appcast.sh $DMG $APP_VERSION"
echo "  then upload $DMG, $STABLE_DMG and appcast.xml to the GitHub Release (see docs/release.md)."
