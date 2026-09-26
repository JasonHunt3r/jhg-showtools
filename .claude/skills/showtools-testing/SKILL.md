---
name: showtools-testing
description: How to launch, drive and measure ShowTools without touching Jason's real app, library or preferences — scratch libraries, the shared preferences-domain trap, axtool, window-not-pgrep checks, audio taps, seeding data with sqlite3, stcli render. Load before launching any test copy or doing a hands-on check.
---

# Testing ShowTools without breaking Jason's app

He uses this app. Everything below exists because something here went
wrong on his Mac, not in theory.

## The scratch library, and the trap behind it

```sh
tools/make-test-library.sh <scratch>/STTest   # scratch library + generated media
open -n --env SHOWTOOLS_LIBRARY=<scratch>/STTest/TestLib.noindex build/ShowTools.app
```

**Never** run against the real library (`~/Pictures/ShowTools Library.noindex`).
Always set `SHOWTOOLS_LIBRARY`.

**A test copy uses a scratch library but shares Jason's real preferences
domain** (`com.jhg.showtools`). That is the trap, and it has two halves:

1. **A test copy that crashes shuts his real app out.** The note
   `TestLaunchRecord` leaves lives in the shared domain, so the refusal is
   read by *his* app, not the next test copy: he gets "Library problem"
   and an empty window with a long scratch path, and **his library looks
   broken**. It happened twice on 2026-09-23. After any test copy dies,
   check `defaults read com.jhg.showtools runningTestLaunches` and clear
   it *before* handing the app back.
2. **Test copies overwrite his layout.** Column widths
   (`EditShowColumns.list` / `.inspector`), window frames and split
   positions all land in his preferences. `defaults export
   com.jhg.showtools <file>` before a test session and put the layout
   keys back after. **`defaults import` only overwrites keys the backup
   already had — it doesn't delete a key a test session created that
   wasn't there before** (found 2026-09-25, testing a new suppression
   checkbox's `UserDefaults` flag: the import "restored" the domain but
   the new key stayed set). Diff the export against a fresh one after
   import, or explicitly `defaults delete` anything the session newly
   wrote, when the feature under test adds its own preference key.

`defaults write com.jhg.showtools editMode show` and the `snapping` switch
are his **real** preferences too (a scratch library doesn't change the
domain). Leave them as found.

Close test copies with `kill` or ⌘Q, not `kill -9` — `kill -9` leaves the
note, and the refused launch that costs is *his*. **Check `pgrep -f
ShowTools.app/Contents/MacOS` after a kill:** a copy that didn't quit
means two copies on one scratch library.

## `pgrep` is not "the app is running"

After a test copy dies badly the next launch opens **no window on
purpose**, while the process still runs. So a pgrep check reports a
healthy app when there is an alert on screen and nothing else. Check for a
**window** (`tools/list-windows.swift`) before calling a launch good.

This is not a detail: the first crash hunt was run with pgrep, so every
refused crash-relaunch counted as a healthy launch, and all its
conclusions had to be withdrawn.

## Driving the UI

Accessibility is granted to the Claude app (2026-09-21).
`tools/axtool.swift` reads the UI (`dump`, `find`, `menustate`) and acts
with real events (`click`, `drag`, `type`, `key`, `menu`).

- **Events go to whatever app is frontmost.** Check the target is
  frontmost before *every* click or keystroke. Typed text has landed in
  Jason's editor, and inside a Claude Code session's own input, coming
  back as fake "user" messages.
- **Get click coordinates from `ax find`/`ax dump`**, never from a
  screenshot. Check the element is on screen first: at a high zoom a
  marker can sit past the window's edge, and axtool refuses the click
  (⇧Z fits the show).
- `axtool click` takes `right|double|cmd|shift|opt|opt-double`. `opt`
  holds the Option key down, which is what `NSEvent.modifierFlags` reads.
- **Keep it cheap.** Read the UI as text; screenshot only when the check
  is about what's on screen.
- **Synthetic clicks and key events aren't proof** of a bug or of a fix.
  Settle a disagreement in a standalone harness, or with one real
  click/keypress from Jason.
- **Drags: watch the screen during the drag, not just the result**, and
  drag at hand speed. `axtool drag` posts its moves back to back, too fast
  to show what a hand sees; a small CGEvent tool stepping every ~25 ms (and
  one that holds perfectly still, posting nothing) reproduced what Jason
  saw. Run it in the background and `screencapture -R` in a loop meanwhile
  — 45 frames of one slow drag found the drag-to-reorder loop that
  result-only checks missed (2026-09-25). Any tool that posts raw events
  must itself refuse unless the target app is frontmost.
- **Launch paths: never pass one containing `..`** —
  `LibraryLocation.isInICloud` loops forever on it (Known issues).
- **Accessibility menu titles can be stale.** AX reported "Undo" while the
  open Edit menu said "Undo Add Marker". Check wording with a screenshot
  of the menu open (AXPress the menu bar item, `screencapture -R`,
  AXCancel).
- **Reading menus through Accessibility validates every item**, like
  opening them, which can surface crashes a mouse user wouldn't hit.
- A crash-relaunch (the crash reporter's Reopen) drops the environment,
  so it points at the **real** library. axtool refuses to drive it.
- **Don't drive the app while Jason is using it**, and tell him before
  restarting it — he often has it open and is trying things.

## Seeding and measuring

- **Seed show data** (markers, songs, image clips) straight into the
  scratch database with `sqlite3`, **with the app quit**. The app only
  reads the database when it loads, and a column a new build adds doesn't
  exist until that build has opened the library once.
- **A test song:** a click on every beat makes timing checkable by eye and
  by ear. Generate a WAV with Python's `wave` module (120 BPM: a 1 kHz
  click every 0.5 s over a quiet 220 Hz tone), `afconvert -f m4af -d aac`
  it, then `stcli ingest <lib> <file>`. `stcli ingest` doesn't add to a
  collection: add a `collection_items` row with `sqlite3` so the song
  shows in the collection list.
- **Checking audio without ears:** a temporary tap on
  `engine.mainMixerNode` writing peak levels against the show clock to a
  scratch file. **Never call `DispatchQueue.main.sync` from the tap
  block:** when the engine stops on the main thread, each waits on the
  other and the app hangs on quit (it happened; the copy needed `kill -9`).
  Read the clock with a lock, or log the tap's own sample time. Remove the
  tap before committing.
- **Frames:** `stcli render <lib> <showID> 960x540 <outdir> <t>…` draws
  through the real Compositor and prints each frame's state,
  `background after #N` included.
- **Screenshots:** `swiftc tools/list-windows.swift` gives window ids,
  then `screencapture -x -o -l <id>`. `tools/contact-sheet.swift` tiles a
  folder of PNGs.
- **A view that looks absent may be drawing with no contrast.** A level
  line on a video block looked missing; sampling the PNG's rows (average
  RGB per row) found it exactly where the geometry predicted — orange at
  35% over an orange video frame. Measure pixels before concluding a view
  isn't there.
- **Measure, don't guess**: write probes to a file in the scratchpad.
  `log show` returns nothing from this app in Claude's sandbox, so a "no
  log lines" check proves nothing. Remove probes before committing.
- Don't shell out to `osascript`/Finder for anything `ls`/`sqlite3`/`xattr`
  can already answer.

## Dev hooks

Listed in `CLAUDE.md`: `SHOWTOOLS_DEV_PLAY`, `SHOWTOOLS_DEV_SHOW`,
`SHOWTOOLS_DEV_IMAGE`, `SHOWTOOLS_DEV_TRANSITION`, `SHOWTOOLS_DEV_OVERLAY`.
A launch with any `SHOWTOOLS_` variable but no `SHOWTOOLS_LIBRARY` opens
nothing and says why.

## BGTools

```sh
open -n --env BGTOOLS_SETTINGS=<scratch settings.json> \
  build/ShowTools.app/Contents/Library/LoginItems/BGTools.app
```

Settings must point at a scratch library, never the real one. It re-reads
the file when it changes and logs to `~/Library/Logs/BGTools.log`.
`BGTOOLS_OPEN_WINDOW=1` opens its window at launch, `BGTOOLS_OPEN_PANEL=1`
its panel, and `AXTOOL_APP=bgtools` lets axtool drive it.

**Control Center tiles only register from an installed app** — `install.sh`
into `~/Applications`, not `build/ShowTools.app`. Caches lie: a new or
renamed tile needs `CURRENT_PROJECT_VERSION` bumped and `killall chronod`.
