#!/bin/sh
# Builds build/BGTools.app with Xcode (via XcodeGen; the Control Center
# extension will need a real Xcode target). Run from anywhere.
set -e
cd "$(dirname "$0")"
xcodegen generate --quiet
xcodebuild -project BGTools.xcodeproj -scheme BGTools -configuration Debug \
  -derivedDataPath ../build/bgtools -quiet build
rm -rf ../build/BGTools.app
cp -R ../build/bgtools/Build/Products/Debug/BGTools.app ../build/
echo "built build/BGTools.app"
