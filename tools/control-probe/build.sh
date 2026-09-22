#!/bin/sh
# Builds the Control Center probe with Xcode (via XcodeGen) and installs it
# in ~/Applications, where the system looks for its tiles.
set -e
cd "$(dirname "$0")"
xcodegen generate --quiet
xcodebuild -project BGControlProbe.xcodeproj -scheme BGControlProbe -configuration Debug \
  -derivedDataPath ../../build/control-probe -quiet build
APP=../../build/control-probe/Build/Products/Debug/BGControlProbe.app
mkdir -p ~/Applications
rm -rf ~/Applications/BGControlProbe.app
cp -R "$APP" ~/Applications/
echo "installed ~/Applications/BGControlProbe.app"
