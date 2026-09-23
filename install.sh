#!/bin/bash
# Install build/ShowTools.app to ~/Applications and launch it once.
#
# The Control Center tiles only register from a scanned location, and only
# after the app that carries them has been launched (measured 2026-09-22,
# tools/nest-probe) — so testing the tiles means this script, not
# build/ShowTools.app.
#
# Caches lie: a new or renamed tile needs CURRENT_PROJECT_VERSION bumped in
# project.yml and `killall chronod`. Expect it, don't debug it.
set -euo pipefail
cd "$(dirname "$0")"

[ -d build/ShowTools.app ] || { echo "error: build/ShowTools.app — run ./make-app.sh first" >&2; exit 1; }

DEST="$HOME/Applications/ShowTools.app"
mkdir -p "$HOME/Applications"

# A copy over a running app would leave it half-written, so both it and the
# nested BGTools are quit first, then the app is replaced whole.
osascript -e 'tell application id "com.jhg.showtools" to quit' >/dev/null 2>&1 || true
pkill -f "ShowTools.app/Contents/Library/LoginItems/BGTools.app" >/dev/null 2>&1 || true
sleep 1

rm -rf "$DEST"
cp -R build/ShowTools.app "$DEST"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
killall chronod >/dev/null 2>&1 || true

# Launched once so macOS registers the tiles. The real library opens here,
# as it should for the installed copy — unless SHOWTOOLS_LIBRARY is set,
# which is how this script gets checked without touching it.
if [ -n "${SHOWTOOLS_LIBRARY:-}" ]; then
    open -n --env SHOWTOOLS_LIBRARY="$SHOWTOOLS_LIBRARY" "$DEST"
else
    open "$DEST"
fi
echo "installed $DEST"
