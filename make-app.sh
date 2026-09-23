#!/bin/bash
# Build build/ShowTools.app with Xcode (spec/xcode-port.md).
#
# One app holds everything: the Control Center tiles in Contents/PlugIns,
# BGTools nested in Contents/Library/LoginItems, Bravura in Resources.
# The libraries, stcli and the tests stay SwiftPM — `swift test` is
# unchanged; only the bundles are built here, because a Control Center
# extension only registers if it was built and signed as a real Xcode
# target.
#
# Tiles only register from an installed copy: to test them, ./install.sh.
set -euo pipefail
cd "$(dirname "$0")"

case "${1:-release}" in
    debug|Debug)     CONFIG=Debug ;;
    release|Release) CONFIG=Release ;;
    *) echo "usage: $0 [debug|release]" >&2; exit 2 ;;
esac

command -v xcodegen >/dev/null 2>&1 || {
    echo "error: XcodeGen isn't installed (brew install xcodegen)" >&2; exit 1
}
xcodegen generate --quiet

xcodebuild -project ShowTools.xcodeproj -scheme ShowTools \
    -configuration "$CONFIG" -derivedDataPath build/xcode -quiet build

rm -rf build/ShowTools.app
cp -R "build/xcode/Build/Products/$CONFIG/ShowTools.app" build/
echo "built build/ShowTools.app"
