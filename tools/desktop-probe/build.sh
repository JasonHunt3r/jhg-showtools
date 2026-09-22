#!/bin/sh
# Builds build/DesktopProbe.app: the Phase 5 test program (see main.swift).
set -e
cd "$(dirname "$0")/../.."
APP=build/DesktopProbe.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
swiftc -O tools/desktop-probe/main.swift -o "$APP/Contents/MacOS/DesktopProbe"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.jhg.desktopprobe</string>
<key>CFBundleName</key><string>DesktopProbe</string>
<key>CFBundleExecutable</key><string>DesktopProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "built $APP"
