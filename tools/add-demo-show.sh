#!/bin/bash
# Add the "Shorty" demo show to an EXISTING library, without touching
# anything already in it.
#
#   tools/add-demo-show.sh [library] [media-dir]
#     library    default: ~/Pictures/ShowTools Library.noindex (the real one)
#     media-dir  default: ~/ShowTools Demo/media
#
# Unlike tools/make-demo-show.sh, this never deletes a library — it ingests
# the demo's media and adds one show. Run it with **the app quit**: the app
# reads the database when it loads, so a show added underneath a running
# copy won't appear and may be overwritten.
#
# What the show is, second by second: spec/history/2026-09-22-alpha-test.md
set -euo pipefail
cd "$(dirname "$0")/.."
LIB="${1:-$HOME/Pictures/ShowTools Library.noindex}"
MEDIA="${2:-$HOME/ShowTools Demo/media}"

[ -f "$LIB/Library.sqlite" ] || { echo "error: no library at $LIB" >&2; exit 1; }
[ -d "$MEDIA" ] || { echo "error: no media at $MEDIA — run tools/make-demo-show.sh first" >&2; exit 1; }
if pgrep -f "ShowTools.app/Contents/MacOS" >/dev/null; then
    echo "error: ShowTools is running. Quit it first (⌘Q), then run this again." >&2
    exit 1
fi

swift build --product stcli >/dev/null
DB="$LIB/Library.sqlite"

echo "==> ingesting the demo media (already-present files are skipped)"
.build/debug/stcli ingest "$LIB" \
    "$MEDIA/photo_01.jpg" "$MEDIA/photo_02.jpg" "$MEDIA/photo_03.jpg" \
    "$MEDIA/photo_06.jpg" "$MEDIA/spinner.gif" \
    "$MEDIA/song-low.m4a" "$MEDIA/song-high.m4a" "$MEDIA/talking-clip.mp4" | sed 's/^/    /'

id_of() { sqlite3 "$DB" "SELECT id FROM items WHERE rel_path LIKE '%$1%' LIMIT 1;"; }
CLIP=$(id_of "talking-clip"); GIF=$(id_of "spinner")
LOW=$(id_of "song-low"); HIGH=$(id_of "song-high")
P1=$(id_of "photo_01"); P2=$(id_of "photo_02"); P3=$(id_of "photo_03"); P4=$(id_of "photo_06")
for v in CLIP GIF LOW HIGH P1 P2 P3 P4; do
    [ -n "${!v}" ] || { echo "error: $v missing from the library after ingest" >&2; exit 1; }
done

# Replace any earlier copy of this demo, so running twice is safe.
sqlite3 "$DB" "DELETE FROM shows WHERE name = 'Shorty';"
.build/debug/stcli show "$LIB" "Shorty" >/dev/null
SHOW=$(sqlite3 "$DB" "SELECT id FROM shows WHERE name = 'Shorty' ORDER BY id DESC LIMIT 1;")

# stcli show builds from every item in the library; this show wants five
# particular slides, so its own are cleared and written by hand.
#
# NOTE: a slide's length is a synthesized Swift enum, so its value is
# wrapped — {"seconds":{"_0":4}}, never {"seconds":4}. The short form
# decodes to nil and the slide silently inherits the show's default.
sqlite3 "$DB" "DELETE FROM slides WHERE show_id = $SHOW;"
add() { sqlite3 "$DB" "INSERT INTO slides (show_id, position, item_id, settings) VALUES ($SHOW, $1, $2, '$3');"; }

add 0 "$P1"   '{"length":{"seconds":{"_0":4}},"fit":"fill","kenBurns":{"auto":{}}}'
add 1 "$P2"   '{"length":{"seconds":{"_0":4}},"fit":"fill","transition":{"style":"cut","duration":0}}'
add 2 "$GIF"  '{"length":{"seconds":{"_0":4}},"fit":"fit","transition":{"style":"dissolve","duration":1}}'
add 3 "$P3"   '{"length":{"seconds":{"_0":2}},"fit":"fill","transition":{"style":"cut","duration":0}}'
add 4 "$CLIP" '{"length":{"seconds":{"_0":10}},"fit":"fit","transition":{"style":"dissolve","duration":1},"audio":{"points":[{"time":0,"level":0.85},{"time":2.6,"level":0.85},{"time":3.0,"level":0},{"time":6.0,"level":0},{"time":6.4,"level":0.85}]}}'

sqlite3 "$DB" "UPDATE shows SET music='[
  {\"itemID\":$LOW,\"start\":0,\"length\":14,\"volume\":0.55,\"fadeIn\":0.5},
  {\"itemID\":$HIGH,\"start\":12,\"length\":12,\"volume\":0.55,\"fadeOut\":1.5}
]' WHERE id = $SHOW;"

sqlite3 "$DB" "UPDATE shows SET overlays='[
  {\"itemID\":$P4,\"start\":4.5,\"length\":3,\"opacity\":0.55,\"fit\":\"fit\"}
]' WHERE id = $SHOW;"

echo
echo "Added “Shorty” (24s) to $LIB"
echo "Open ShowTools and it's in the sidebar. What to look for: spec/history/2026-09-22-alpha-test.md"
