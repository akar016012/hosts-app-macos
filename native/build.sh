#!/bin/bash
# Build HostsEditor.app — a native SwiftUI app that edits /etc/hosts, elevating
# only the file write via the native macOS admin dialog.
set -e
cd "$(dirname "$0")"

APP="HostsEditor.app"
BIN="HostsEditor"
# Version stamped into Info.plist. Defaults to 1.0 for local dev builds;
# release.sh overrides it with the release version so the bundle, DMG name,
# and CHANGELOG/tag stay in sync.
APP_VERSION="${APP_VERSION:-1.0}"

# ── Sparkle (auto-update framework) ───────────────────────────────────────────
# Pinned + checksum-verified, downloaded into a gitignored cache on first build
# and reused thereafter. Bumping SPARKLE_VERSION means updating SPARKLE_SHA256
# (printed by: shasum -a 256 Vendor/Sparkle-<v>.tar.xz). The bin/ tools
# (generate_keys, sign_update, generate_appcast) used by release.sh live here too.
SPARKLE_VERSION="2.9.3"
SPARKLE_SHA256="74a07da821f92b79310009954c0e15f350173374a3abe39095b4fc5096916be6"
SPARKLE_DIR="Vendor/Sparkle-${SPARKLE_VERSION}"
SPARKLE_FRAMEWORK="$SPARKLE_DIR/Sparkle.framework"
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
  echo "→ Fetching Sparkle ${SPARKLE_VERSION}…"
  mkdir -p "$SPARKLE_DIR"
  TARBALL="Vendor/Sparkle-${SPARKLE_VERSION}.tar.xz"
  curl -fL --retry 3 -o "$TARBALL" \
    "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
  echo "$SPARKLE_SHA256  $TARBALL" | shasum -a 256 -c - \
    || { echo "✗ Sparkle checksum mismatch — refusing to build."; exit 1; }
  tar -xJf "$TARBALL" -C "$SPARKLE_DIR"
fi

echo "→ Compiling app…"
APP_SOURCES=(
  HostsEditor.swift
  Core/*.swift
  UI/*.swift
)
# -F so `import Sparkle` resolves via the framework's bundled module map; the
# rpath lets the embedded copy in Contents/Frameworks load at runtime.
swiftc -O -parse-as-library "${APP_SOURCES[@]}" \
  -F "$SPARKLE_DIR" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$BIN"

echo "→ Compiling privileged helper…"
swiftc -O HostsHelper.swift -o com.etchosts.hostshelper

echo "→ Assembling app bundle…"
rm -rf "$APP"
# SMAppService requires the daemon executable in Contents/MacOS and its launchd
# plist in Contents/Library/LaunchDaemons (managed in-bundle, not /Library).
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" \
         "$APP/Contents/Library/LaunchDaemons" "$APP/Contents/Frameworks"
mv "$BIN" "$APP/Contents/MacOS/$BIN"
mv com.etchosts.hostshelper "$APP/Contents/MacOS/com.etchosts.hostshelper"
chmod +x "$APP/Contents/MacOS/com.etchosts.hostshelper"

# Embed Sparkle.framework (ditto preserves the version symlinks + perms Sparkle
# relies on). It is signed inside-out below, before the app bundle is sealed.
/usr/bin/ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

cat > "$APP/Contents/Library/LaunchDaemons/com.etchosts.hostshelper.plist" <<DAEMON
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.etchosts.hostshelper</string>
  <key>BundleProgram</key><string>Contents/MacOS/com.etchosts.hostshelper</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>/var/log/hostshelper.log</string>
</dict>
</plist>
DAEMON

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>HostsEditor</string>
  <key>CFBundleDisplayName</key><string>Hosts</string>
  <key>CFBundleIdentifier</key><string>com.etchosts.hostseditor</string>
  <key>CFBundleVersion</key><string>$APP_VERSION</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>HostsEditor</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <!-- Sparkle auto-update. Feed is an appcast published as a GitHub Release
       asset (release.sh generates + signs it). SUPublicEDKey is the public half
       of the EdDSA key whose private half lives in the release machine's
       keychain; it is safe to ship. -->
  <key>SUFeedURL</key><string>https://github.com/akar016012/hosts-app-macos/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>z8zs16OenRvH760NohazXoxcj5+Gb53vMSLYIDmLXv8=</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict>
</plist>
PLIST

# Build an .icns from the native SVG icon if possible (non-fatal).
ICONSET="AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
if qlmanage -t -s 1024 -o "$ICONSET" AppIcon.svg >/dev/null 2>&1 && [ -f "$ICONSET/AppIcon.svg.png" ]; then
  B="$ICONSET/AppIcon.svg.png"
  sips -z 16 16     "$B" --out "$ICONSET/icon_16x16.png"      >/dev/null 2>&1
  sips -z 32 32     "$B" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null 2>&1
  sips -z 32 32     "$B" --out "$ICONSET/icon_32x32.png"      >/dev/null 2>&1
  sips -z 64 64     "$B" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null 2>&1
  sips -z 128 128   "$B" --out "$ICONSET/icon_128x128.png"    >/dev/null 2>&1
  sips -z 256 256   "$B" --out "$ICONSET/icon_128x128@2x.png" >/dev/null 2>&1
  sips -z 256 256   "$B" --out "$ICONSET/icon_256x256.png"    >/dev/null 2>&1
  sips -z 512 512   "$B" --out "$ICONSET/icon_256x256@2x.png" >/dev/null 2>&1
  sips -z 512 512   "$B" --out "$ICONSET/icon_512x512.png"    >/dev/null 2>&1
  cp  "$B"               "$ICONSET/icon_512x512@2x.png"
  rm -f "$ICONSET/AppIcon.svg.png"
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" >/dev/null 2>&1 \
    && echo "→ Icon built" || echo "→ Icon skipped (iconutil failed)"
else
  echo "→ Icon skipped (could not render svg)"
fi
rm -rf "$ICONSET"

# SMAppService refuses to register an ad-hoc ("-") signed bundle, so sign with a
# real identity (a free Apple Development cert works for local testing; a paid
# Developer ID is only needed to distribute to other Macs). Resolution order:
#   1. SIGN_IDENTITY=… ./build.sh   (env override)
#   2. native/.signid               (gitignored local file holding your identity)
#   3. placeholder                  (so the repo never ships a personal identity)
SIGN_IDENTITY="${SIGN_IDENTITY:-$( [ -f .signid ] && cat .signid || echo 'Apple Development: you@example.com (TEAMID)' )}"
echo "→ Signing with: $SIGN_IDENTITY"
# A secure timestamp is required for notarization but needs network and slows
# local dev builds, so it is opt-in: release.sh sets RELEASE=1 to enable it.
TS_FLAG=""; [ -n "${RELEASE:-}" ] && TS_FLAG="--timestamp"
# Helper first (nested code), then the app bundle seals it. Hardened runtime on both.
# Pin the helper's identifier — codesign otherwise treats ".hostshelper" as a file
# extension and truncates the identifier to "com.etchosts".
codesign --force --options runtime $TS_FLAG --identifier com.etchosts.hostshelper \
  --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/com.etchosts.hostshelper"
# Sparkle ships pre-signed by its authors; re-sign every nested executable with
# our identity (inside-out) so notarization passes and the app's seal is
# consistent. Versions/B is Sparkle 2.x's current version dir.
SPK="$APP/Contents/Frameworks/Sparkle.framework"
for nested in \
  "Versions/B/XPCServices/Installer.xpc" \
  "Versions/B/XPCServices/Downloader.xpc" \
  "Versions/B/Autoupdate" \
  "Versions/B/Updater.app"; do
  [ -e "$SPK/$nested" ] && \
    codesign --force --options runtime $TS_FLAG --sign "$SIGN_IDENTITY" "$SPK/$nested"
done
codesign --force --options runtime $TS_FLAG --sign "$SIGN_IDENTITY" "$SPK"
codesign --force --options runtime $TS_FLAG --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict "$APP" && echo "→ Signed & verified"

echo ""
echo "✓ Built $(pwd)/$APP"
echo "  Launch it with:  open $APP"
