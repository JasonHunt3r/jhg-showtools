#!/bin/sh
# Builds both login probes, ad hoc signed, into ~/Applications, and writes
# the LaunchAgent for the .la copy. See main.swift. Undo with ./remove.sh.
set -e
cd "$(dirname "$0")"
mkdir -p ../../build ~/Applications
swiftc -O main.swift -o ../../build/LoginProbe
for kind in sm la; do
  APP=~/Applications/LoginProbe-$kind.app
  rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
  cp ../../build/LoginProbe "$APP/Contents/MacOS/LoginProbe"
  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.jhg.loginprobe.$kind</string>
<key>CFBundleName</key><string>LoginProbe $kind</string>
<key>CFBundleExecutable</key><string>LoginProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
  codesign --force --sign - "$APP"
done
mkdir -p ~/Library/LaunchAgents
cat > ~/Library/LaunchAgents/com.jhg.loginprobe.la.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.jhg.loginprobe.la</string>
<key>ProgramArguments</key><array>
  <string>$HOME/Applications/LoginProbe-la.app/Contents/MacOS/LoginProbe</string>
  <string>--from-launchagent</string>
</array>
<key>RunAtLoad</key><true/>
</dict></plist>
PLIST
echo "built ~/Applications/LoginProbe-sm.app, LoginProbe-la.app and the LaunchAgent"
