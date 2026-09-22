#!/bin/bash
# Wrap the SwiftPM executable in a .app bundle.
#
# A bare SwiftPM binary has no Info.plist, so macOS gives it no Dock icon,
# no proper menu bar and no ⌘Q. The bundle makes it behave like an app.
# Same approach as CutSim (jhg-cutcheck/sim/make-app.sh).
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
swift build -c "$CONFIG" --product ShowToolsApp

APP="build/ShowTools.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/$CONFIG/ShowToolsApp" "$APP/Contents/MacOS/ShowTools"
# Bravura, the music font (SIL OFL 1.1, licence alongside), for rhythm
# notation. ATSApplicationFontsPath below loads it for the app alone.
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"

# BGTools, the desktop companion (spec/bgtools.md). ShowTools carries it and
# copies it to ~/Applications when the desktop is first turned on. Building
# it needs Xcode and XcodeGen; without them the app is built without it and
# "Set Up Desktop Show…" says so.
if command -v xcodegen >/dev/null 2>&1; then
    BGTools/build.sh >/dev/null
    cp -R build/BGTools.app "$APP/Contents/Resources/BGTools.app"
else
    echo "note: XcodeGen isn't installed, so this build carries no BGTools"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>ShowTools</string>
    <key>CFBundleDisplayName</key>        <string>ShowTools</string>
    <key>CFBundleExecutable</key>         <string>ShowTools</string>
    <key>CFBundleIdentifier</key>         <string>com.jhg.showtools</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1</string>
    <key>CFBundleVersion</key>            <string>1</string>
    <key>LSMinimumSystemVersion</key>     <string>14.0</string>
    <key>NSHighResolutionCapable</key>    <true/>
    <key>NSSupportsAutomaticTermination</key> <false/>
    <key>ATSApplicationFontsPath</key>    <string>Fonts</string>
    <!-- Files dragged within the app (from the Collection Browser). -->
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>        <string>com.jhg.showtools.items</string>
            <key>UTTypeDescription</key>       <string>ShowTools library files</string>
            <key>UTTypeConformsTo</key>        <array><string>public.data</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" 2>/dev/null || true
echo "built $APP"
