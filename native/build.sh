#!/bin/bash
# Build HostsEditor.app — a native SwiftUI app that edits /etc/hosts, elevating
# only the file write via the native macOS admin dialog.
set -e
cd "$(dirname "$0")"

APP="HostsEditor.app"
BIN="HostsEditor"

echo "→ Compiling app…"
APP_SOURCES=(
  HostsEditor.swift
  Core/*.swift
  UI/*.swift
)
swiftc -O -parse-as-library "${APP_SOURCES[@]}" -o "$BIN"

echo "→ Compiling privileged helper…"
swiftc -O HostsHelper.swift -o com.aditya.hostshelper
codesign --force --sign - com.aditya.hostshelper >/dev/null 2>&1 || true

echo "→ Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv "$BIN" "$APP/Contents/MacOS/$BIN"
mv com.aditya.hostshelper "$APP/Contents/Resources/com.aditya.hostshelper"
chmod +x "$APP/Contents/Resources/com.aditya.hostshelper"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>HostsEditor</string>
  <key>CFBundleDisplayName</key><string>Hosts</string>
  <key>CFBundleIdentifier</key><string>com.aditya.hostseditor</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>HostsEditor</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
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

echo "→ Ad-hoc signing…"
# Sign the bundled helper, then the app. No entitlements: the Secure Enclave key
# uses the legacy keychain (kSecUseDataProtectionKeychain=false), so no
# keychain-access-group entitlement is needed — and entitlements would get the
# ad-hoc app killed by AMFI on launch.
codesign --force --sign - "$APP/Contents/Resources/com.aditya.hostshelper" >/dev/null 2>&1 || true
codesign --force --sign - "$APP" >/dev/null 2>&1 && echo "→ Signed"
xattr -cr "$APP" 2>/dev/null || true

echo ""
echo "✓ Built $(pwd)/$APP"
echo "  Launch it with:  open $APP"
