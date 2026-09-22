#!/bin/sh
# Takes the nest probe out again (the log is kept).
pkill -x NestHelper 2>/dev/null || true
pkill -x NestHost 2>/dev/null || true
rm -rf ~/Applications/NestProbe.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u ~/Applications/NestProbe.app 2>/dev/null || true
killall chronod 2>/dev/null || true
echo "nest probe removed"
