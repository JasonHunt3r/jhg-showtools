#!/bin/sh
# Builds and installs ~/Applications/NestProbe.app (host + nested helper +
# a Control Center tile). Remove with remove.sh.
set -e
cd "$(dirname "$0")"
xcodegen generate --quiet
xcodebuild -project NestProbe.xcodeproj -scheme NestHost -configuration Debug \
  -derivedDataPath ../../build/nest-probe -quiet build
rm -rf ~/Applications/NestProbe.app
mkdir -p ~/Applications
cp -R ../../build/nest-probe/Build/Products/Debug/NestHost.app ~/Applications/NestProbe.app
echo "installed ~/Applications/NestProbe.app"
