#!/bin/bash
# Reset HostsEditor to a clean state for end-to-end onboarding testing.
#
# Default: a true first-run wipe — removes the local profile/identity, PIN,
# session signing key, schemes, history, avatar, the daemon's root-owned
# enrollment, and all app preferences.
#
#   ./reset-state.sh              # full first-run wipe
#   ./reset-state.sh --keep-data  # keep schemes/history/avatar & prefs; wipe only
#                                 # the security/identity state (signing key, PIN,
#                                 # daemon enrollment) so the next unlock re-enrolls
#
# NOTE: the privileged daemon's SMAppService registration (the "Hosts" entry under
# System Settings → Login Items) is owned by macOS Background Task Management and
# CANNOT be unregistered from the shell. To re-test the Login Items APPROVAL step,
# toggle "Hosts" off there before relaunching — this script reminds you at the end.

set -euo pipefail

BUNDLE_ID="com.etchosts.hostseditor"
ROOT_DIR="/Library/Application Support/HostsHelper"          # root-owned daemon state
USER_DIR="$HOME/Library/Application Support/HostsEditor"     # app's per-user state

KEEP_DATA=0
[ "${1:-}" = "--keep-data" ] && KEEP_DATA=1

echo "→ Quitting HostsEditor…"
osascript -e 'tell application "HostsEditor" to quit' 2>/dev/null || true
sleep 1

if [ "$KEEP_DATA" -eq 1 ]; then
  echo "→ Removing security/identity state (keeping schemes, history, avatar)…"
  rm -f "$USER_DIR/session-signing.key" "$USER_DIR/pin.json" "$USER_DIR/pin-attempts.json"
else
  echo "→ Removing all user state ($USER_DIR)…"
  rm -rf "$USER_DIR"
  echo "→ Removing app preferences ($BUNDLE_ID)…"
  defaults delete "$BUNDLE_ID" 2>/dev/null || true
fi

echo "→ Removing daemon enrollment — sudo required ($ROOT_DIR)…"
sudo rm -rf "$ROOT_DIR"

echo
echo "✓ Done. Local state reset."
echo
echo "To also re-test the Login Items approval step (full first run):"
echo "  1. System Settings → General → Login Items & Extensions"
echo "  2. Under 'Allow in the Background', toggle OFF 'Hosts' (unregisters the daemon)"
echo "  3. Relaunch HostsEditor — you'll get the approval prompt, then Touch ID + enroll."
