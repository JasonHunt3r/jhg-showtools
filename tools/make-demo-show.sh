#!/bin/bash
# Build the "Shorty" demo library: a 24-second show laid out so each thing
# worth checking happens on its own, one at a time, with nothing else going
# on to confuse it. Made for Jason's alpha test drive (spec/history/2026-09-22-alpha-test.md).
#
#   tools/make-demo-show.sh [dir]        (default: ~/ShowTools Demo)
#
# Open it from the app: File ▸ Open Library… → <dir>/Shorty.noindex
#
# What the show is built to show, in order:
#   0–4s   a still with Ken Burns, over a click track on every beat
#   4s     a HARD CUT, landing exactly on a beat
#   4–8s   a still, then a 1s dissolve
#   8–12s  an animated GIF (does it run at the right speed?)
#   12–14s the two songs CROSSFADE (equal power: no dip in the middle)
#   14–24s a VIDEO slide, playing its own frames, whose own sound is turned
#          up, then dropped to silence for three seconds, then brought back,
#          all while the song keeps playing underneath
set -euo pipefail
cd "$(dirname "$0")/.."
DIR="${1:-$HOME/ShowTools Demo}"
LIB="$DIR/Shorty.noindex"
mkdir -p "$DIR/media" "$DIR/bin"

echo "==> generating pictures"
swiftc -O tools/gen-test-media.swift -o "$DIR/bin/gen-test-media"
"$DIR/bin/gen-test-media" "$DIR/media" >/dev/null

echo "==> generating songs and a talking-ish video soundtrack"
python3 - "$DIR/media" <<'PY'
import math, struct, sys, wave

out = sys.argv[1]

def write(name, seconds, fn):
    rate = 44100
    frames = []
    for i in range(int(rate * seconds)):
        v = max(-1.0, min(1.0, fn(i / rate)))
        frames.append(struct.pack('<h', int(v * 32767)))
    w = wave.open(f"{out}/{name}.wav", 'w')
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
    w.writeframes(b''.join(frames)); w.close()

# Two songs, 120 BPM (a beat every 0.5s), different in pitch so the
# crossfade is obvious by ear: you should hear one become the other
# without the loudness dipping in the middle.
def song(click_hz, bed_hz):
    def f(t):
        v = 0.14 * math.sin(2 * math.pi * bed_hz * t)
        beat = t % 0.5
        if beat < 0.03:
            v += 0.6 * math.sin(2 * math.pi * click_hz * t) * math.exp(-beat * 90)
        return v
    return f

write("song-low",  16, song(1000, 220))
write("song-high", 16, song(1500, 330))

# The video's own soundtrack: a warbling tone, nothing like the clicks, so
# when the level line drops it you can tell instantly which sound went.
def warble(t):
    return 0.5 * math.sin(2 * math.pi * (600 + 120 * math.sin(2 * math.pi * 1.5 * t)) * t)
write("video-tone", 10, warble)
PY

for f in song-low song-high video-tone; do
    afconvert -f m4af -d aac "$DIR/media/$f.wav" "$DIR/media/$f.m4a" >/dev/null
    rm "$DIR/media/$f.wav"
done

swift build --product stcli >/dev/null

# The video slide needs a real video that has sound AND a picture that
# visibly moves, so it's obvious whether it plays or holds one frame.
# Easiest honest way to make one: export a small show with ShowTools' own
# exporter. (It also dogfoods the thing being tested.)
echo "==> building a 10s video with sound"
SRC="$DIR/src.noindex"
rm -rf "$SRC"
.build/debug/stcli ingest "$SRC" "$DIR/media/photo_01.jpg" "$DIR/media/photo_02.jpg" \
    "$DIR/media/photo_03.jpg" "$DIR/media/photo_04.jpg" "$DIR/media/photo_05.jpg" \
    "$DIR/media/video-tone.m4a" >/dev/null
.build/debug/stcli show "$SRC" "src" >/dev/null
SRCDB="$SRC/Library.sqlite"
# Five 2-second slides, hard cuts, and the warble over all of it.
sqlite3 "$SRCDB" "DELETE FROM slides WHERE item_id = 6;"
sqlite3 "$SRCDB" "UPDATE slides SET settings='{\"length\":{\"seconds\":{\"_0\":2}},\"transition\":{\"style\":\"cut\",\"duration\":0},\"fit\":\"fill\"}';"
sqlite3 "$SRCDB" "UPDATE shows SET music='[{\"itemID\":6,\"start\":0,\"length\":10,\"volume\":1}]';"
rm -f "$DIR/media/talking-clip.mp4"
.build/debug/stcli movie "$SRC" 1 640x400 "$DIR/media/talking-clip.mp4" 30 h264 >/dev/null
rm -rf "$SRC"
rm "$DIR/media/video-tone.m4a"

echo "==> building the Shorty library"
rm -rf "$LIB"
.build/debug/stcli ingest "$LIB" "$DIR/media" >/dev/null
.build/debug/stcli show "$LIB" "Shorty" >/dev/null
DB="$LIB/Library.sqlite"

id_of() { sqlite3 "$DB" "SELECT id FROM items WHERE rel_path LIKE '%$1%' LIMIT 1;"; }
CLIP=$(id_of "talking-clip")
GIF=$(id_of "spinner")
LOW=$(id_of "song-low")
HIGH=$(id_of "song-high")
P1=$(id_of "photo_01"); P2=$(id_of "photo_02"); P3=$(id_of "photo_03"); P4=$(id_of "photo_06")

# One show, built by hand: five slides, each demonstrating one thing.
#
# NOTE for anyone editing these by hand: a slide's length is a synthesized
# Swift enum, so its value is wrapped — {"seconds":{"_0":4}}, never
# {"seconds":4}. The short form decodes to nil and the slide silently
# inherits the show's default length instead. Measured 2026-09-22.
sqlite3 "$DB" "DELETE FROM slides WHERE show_id = 1;"
add() { sqlite3 "$DB" "INSERT INTO slides (show_id, position, item_id, settings) VALUES (1, $1, $2, '$3');"; }

# 0–4s  Ken Burns on a still, so motion is visible from the first second.
add 0 "$P1" '{"length":{"seconds":{"_0":4}},"fit":"fill","kenBurns":{"auto":{}}}'
# 4–8s  A HARD CUT onto a beat. No transition at all: it should snap.
add 1 "$P2" '{"length":{"seconds":{"_0":4}},"fit":"fill","transition":{"style":"cut","duration":0}}'
# 8–12s An animated GIF, reached by a 1s dissolve.
add 2 "$GIF" '{"length":{"seconds":{"_0":4}},"fit":"fit","transition":{"style":"dissolve","duration":1}}'
# 12–14s A still over the songs' crossfade, so the ear is on the music.
add 3 "$P3" '{"length":{"seconds":{"_0":2}},"fit":"fill","transition":{"style":"cut","duration":0}}'
# 14–24s The video slide: its own frames, and its own sound turned up,
#        dropped to nothing for three seconds, then brought back.
add 4 "$CLIP" '{"length":{"seconds":{"_0":10}},"fit":"fit","transition":{"style":"dissolve","duration":1},"audio":{"points":[{"time":0,"level":0.85},{"time":2.6,"level":0.85},{"time":3.0,"level":0},{"time":6.0,"level":0},{"time":6.4,"level":0.85}]}}'

# Two songs that overlap 12–14s, which is where they crossfade.
sqlite3 "$DB" "UPDATE shows SET music='[
  {\"itemID\":$LOW,\"start\":0,\"length\":14,\"volume\":0.55,\"fadeIn\":0.5},
  {\"itemID\":$HIGH,\"start\":12,\"length\":12,\"volume\":0.55,\"fadeOut\":1.5}
]' WHERE id = 1;"

# A lane image over the hard cut, to exercise the images row.
sqlite3 "$DB" "UPDATE shows SET overlays='[
  {\"itemID\":$P4,\"start\":4.5,\"length\":3,\"opacity\":0.55,\"fit\":\"fit\"}
]' WHERE id = 1;"

echo
echo "Shorty is ready:  $LIB"
echo "Open it with File ▸ Open Library…  (the show is called Shorty, 24 seconds)"
echo "What to listen and look for: spec/history/2026-09-22-alpha-test.md"
