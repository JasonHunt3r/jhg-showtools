#!/bin/sh
# Takes the login probes back out: unregisters the SMAppService one, removes
# the LaunchAgent and both apps. The log (~/Library/Logs/BGLoginProbe.log)
# is kept.
~/Applications/LoginProbe-sm.app/Contents/MacOS/LoginProbe --unregister 2>/dev/null || true
launchctl bootout gui/$(id -u)/com.jhg.loginprobe.la 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.jhg.loginprobe.la.plist
rm -rf ~/Applications/LoginProbe-sm.app ~/Applications/LoginProbe-la.app
echo "login probes removed"
