#!/bin/bash
# Build a scratch library with generated media and one show, for testing
# without touching the real library in ~/Pictures.
#
#   tools/make-test-library.sh [dir]       (default: /tmp/ShowToolsTest)
#
# Then:  open -n --env SHOWTOOLS_LIBRARY="$dir/TestLib.noindex" build/ShowTools.app
#
# Media: 8 numbered photos in assorted sizes and orientations, a HEIC, a
# 6-frame GIF and a 4-second video, all with a grid so Ken Burns motion shows.
set -euo pipefail
cd "$(dirname "$0")/.."
DIR="${1:-/tmp/ShowToolsTest}"
mkdir -p "$DIR/media" "$DIR/bin"

swiftc -O tools/gen-test-media.swift -o "$DIR/bin/gen-test-media"
"$DIR/bin/gen-test-media" "$DIR/media"

swift build --product stcli >/dev/null
rm -rf "$DIR/TestLib.noindex"
.build/debug/stcli ingest "$DIR/TestLib.noindex" "$DIR/media"
.build/debug/stcli show "$DIR/TestLib.noindex" "Test Show"

# A different transition on most slides, and Auto Ken Burns, so a play-through
# exercises the renderer.
DB="$DIR/TestLib.noindex/Library.sqlite"
styles=(dissolve copyMachine push pageCurl ripple bars cover disintegrate mod flash)
for i in "${!styles[@]}"; do
    pos=$((i + 1))
    sqlite3 "$DB" "UPDATE slides SET settings='{\"transition\":{\"style\":\"${styles[$i]}\",\"duration\":1,\"direction\":\"left\"}}' WHERE position=$pos"
done
sqlite3 "$DB" "UPDATE shows SET defaults=json_set(defaults,'\$.kenBurns',json('{\"auto\":{}}'))"
echo "test library: $DIR/TestLib.noindex"
