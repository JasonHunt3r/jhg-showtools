# ShowTools — handoff, 2026-09-22 (end of day three)

For the next session. Read `CLAUDE.md` (rules) and `spec/plan.md` (every
decision, phase by phase) first. This file is the state of play. The repo
is `~/Projects/ShowTools`, pushed to **github.com/JasonHunt3r/jhg-showtools**
(public, `main`).

## Start here (end of 2026-09-22)

**Phase 4 (setlist export / import): 4a–4d are built.** Jason answered
every question on 2026-09-22; the plan's Phase 4 section was rewritten to
fit what a show holds now (`show.json` for everything, `show.tsv` to read
and edit, metadata stripped by default, song tags kept). **Next: 4e**, a
hands-on round trip with Jason, including an edit to `show.tsv` in Numbers
(find out whether Numbers saves TSV; if it only writes CSV, import could
read `show.csv` too).

Where things stand: Phase 3 and 3b are built; 172 tests; schema 12. Image
stickiness (the end of Phase 3) stays parked until Jason has made a first
real show.

## Phase 4a: core export (2026-09-22)

- `Setlist.swift`: `SetlistManifest` (show.json, decoded field by field
  with lenient lists), `SetlistTSV` (text forms for every cell),
  `SetlistExport.plan` (reads the library, on its thread; fails with
  `missingFiles` before writing anything) and `SetlistExport.write`
  (off the main thread; builds a hidden sibling folder and moves it into
  place; replaces an earlier export of the same show via `discard`, the
  Trash by default; refuses any other non-empty folder).
- `MetadataStrip.swift`: measured before it was written (see the plan's
  Privacy bullet). Each stripped copy is read back; a failure falls back to
  an unstripped copy, listed in `Result.notStripped` for 4c to show.
  Songs keep their tags (Jason): only personal ones come off
  (`MetadataStrip.isPersonal`).
- `Library.identifier()`: a random id kept in `library_settings` (no
  schema change), so an export knows which library and show it came from.

## Phase 4d: Import Show… (2026-09-22)

- `ImportShowPanel.swift`: File ▸ Import Show… (no shortcut). A folder
  panel with "Make a collection for it" and a note naming the collection
  the show otherwise goes into. `AppModel.importShow` reads the folder off
  the main thread, imports what the library lacks through the ordinary
  `importFiles` (so the Import banner shows), then `makeShow`; new files
  are those not in `itemsByID` before. Problems go in one alert afterwards.
- File ▸ Import… gains "Make a collection for each folder".
- `newCollection(named:itemIDs:select:)` now takes a name and returns the id.
- Checked in the app on scratch libraries (axtool): import back into the
  exporting library (new "Test Show 2" in a new collection, no files
  copied, all 11 slides' settings identical with seeds = original ids,
  and defaults, rows, music, markers, editor state the same); import into
  an empty library (11 added, all in the collection); Import… with two
  folders (collections "Holiday Pics" and "Beach", from `Beach.noindex`).
- A new library already has an "Untitled Collection", so Import Show's
  "no collection yet" case (box forced on) practically never shows.

## Phase 4c: Export Show… (2026-09-22)

- `ExportPanel.swift`: File ▸ Export Show… (⇧⌘E; the show in the window,
  else the one selected in the sidebar). A Save panel names the folder;
  its accessory has "Hide from Spotlight" (on when the library is private)
  and a line saying whether metadata will be stripped. `SetlistExport.plan`
  runs on the main actor (a missing file is an alert pointing at Relink),
  `write` runs in a Task, and `ExportBanner` shows progress, then the
  result: Show in Finder, Done, and a Details menu listing any file that
  kept its metadata. The menu item is off while an export runs.
- Settings ▸ Export: "Strip metadata from exported files"
  (`exportStripsMetadata`, on unless set).
- Checked in the app on a scratch library (axtool): the menu item enabled,
  the panel's name and checkbox, Export writing all 11 test files
  (video, HEIC, GIF included) stripped with no warnings, the banner's
  text, and the Settings section. Not checked by hand: re-exporting over
  the earlier folder (it goes to the real Trash; covered by tests).
- A stale test-launch note from 2026-09-21 (pid 97389) was deleted from
  the real prefs at Jason's request.

## Phase 4b: core import (2026-09-22)

- `SetlistImport.swift`: `SetlistTSV.parse` and a parser for every cell
  form; `SetlistImport.read` (off the main thread: merges JSON and TSV,
  hashes the folder's files, collects problems), `filesToImport` (what the
  library lacks: library hash first, then the file's own) and `makeShow`
  (on the library's thread, after the app has imported those files; gives
  ratings and tags only to the items just imported; puts the show and all
  its files into the collection it's given).
- The app's part (4d): `read`, then its own import of `filesToImport`
  (which already dedupes by hash), then `makeShow` with the new item ids.
- `SlideSettings.kenBurnsSeed` (additive, field by field): the timeline
  seeds auto Ken Burns from it before `slide.id`. Import sets it to the
  exported id; Duplicate clears it on the copy, so copies still get their
  own move.

## Step 6 (2026-09-22: tested and agreed)

Step 6, beat detection, was tested on **macOS 27.0** on 2026-09-22 and
passed all seven checks below. It was tested with the click track and with
two real songs Jason supplied, which are kept **outside the public repo**
in `~/Projects/ShowTools-TestMedia/`. Never copy them into the repo.
Jason agreed proposals 1–6 as built, with two changes:
- **×2 / ÷2 correct the bar starts too** (`da72cfa`). Before, they did
  nothing in "Every N bars" mode.
- **Fit slides only resizes slides.** It never splits one. Jason read
  "re-cut" as splitting, so the tooltip and plan now say "resize". The
  behaviour didn't change. Fit starts switched on, and he wants that.

Undo and Redo in the Edit menu already carry each edit's name ("Undo Add
Marker"). Accessibility reports a stale plain "Undo", so check menu wording
with a screenshot of the open menu, not with `axtool`.

**Step 7 (rhythm patterns) is built too**, 7a–7g, all on 2026-09-22 (see
"Step 7" below). Image stickiness (end of Phase 3) is still to settle.

## Phase 3b: Delete by context, Find Similar, Keep One (2026-09-22)

**Phase 3b was replanned with Jason** (plan: "Find Similar, and Delete by
context"): exact duplicates can't exist (unique hash, import skips them),
so it's Group Similar / Show Similar with a slider, and Keep One for a
series. **Step 1, Delete by context, is BUILT** (2026-09-22): in a
collection Delete removes from the collection (undoable) and ⌘Delete
deletes from the library after asking, in the grid and in Edit Show's
collection column; Remove from Collection and Delete Collection are
undoable (a deleted collection comes back with its shows, same ids:
`Library.snapshotCollection` / `restoreCollection`; transactions now nest).
Checked in a scratch copy, and a DB backup was taken first.
**Fixed (Jason confirmed the bug by hand):** a click on a grid tile never
gave the grid the keyboard, so Delete did nothing in the Library or a
collection (Tab worked). Three SwiftUI focus changes didn't fix it
(focus on the grid only, focus set a turn later, onDeleteCommand moved
onto the grid; none proven to matter). What works: Delete and ⌘Delete
are caught by `SingleKeys` like ⌘Delete already was, only with a
selection, never while text is edited or a list (the sidebar) has the
keyboard. Checked: collection Delete + ⌘Z, Library Delete asks, typing
in Search and the sidebar unaffected.
**Find Similar is BUILT** (2026-09-22). Measured first (scratch script
over the macOS aerial screensaver stills plus variants): Vision's distance
is plain Euclidean on the 768-float unit print; shrinking to **299 px**
before Vision keeps copies at 0.09–0.18 and a light crop at 0.22, while
the closest different photos are 0.39+, a "series" (Numbers' marble
textures) 0.47–0.72, unrelated ~1.0 (512 px gave copies 0.35–0.38; whole
images scattered to 0.63). `SimilarityIndex` (core, 5 tests): every pair
within 0.75 at once (Accelerate sgemm in 256-row blocks), union-find
groups for any tighter setting, `similar(to:)` closest first.
`Fingerprints` (app): Vision revision 2 pinned, cached as
`Cache/Prints/<hash>.r2.f32`, worked out 4 at a time with progress.
Grid bar: **Similar** (Group Similar, sections "N alike") and a
Close–Loose slider (0.15–0.75, default 0.45); **Show Similar** on a
picture's right-click ("Like “name”" with ✕). Checked in a scratch copy:
the Golden Gate photo and its 5 variants group; 10 → 27 of 51 grouped
from default to Loose; Show Similar lists the variants closest first.
**Keep One is BUILT** (2026-09-22). `KeepOne` (core, 3 tests): suggested
keeper = most pixels, then best rating, then first added; a file any show
uses stays (Library and collection alike); only files going to the Trash
hand on tags (keeper's first) and a higher rating. `AppModel.keepOne` runs
it in one undo group (removeFromCollection, or setTags + setRating +
deleteItems). `KeepOneSheet`: a "Keep One…" button on each group header;
cards with size, file size, format, date, rating, shows; Keep / To Trash /
Leaves / Stays badges; a summary line. Checked: the Golden Gate group,
5 to the Trash, keeper took "bridge" and 4 stars, one ⌘Z brought all back
(files out of the Trash, tags and ratings as before); a group whose
files are both in the show keeps both ("1 stays"), Keep One disabled.
**Phase 3b is done.** Next: plan Phase 4 (see "Start here").

## Where it stands

| Phase | State |
|---|---|
| 1 Library + player | Built |
| 2 Composer (Edit Slides / Edit Show) | Built |
| **2a** Framing, rotation, match cuts | **Built**, except presets (Flush), which are deferred |
| **2b** Library manager | **Built** |
| **2c** The lane: transitions row + images row | **Built** |
| **3** Music + timeline | **All 7 steps built** (6 and 7 on 2026-09-22). Left: settle image stickiness with Jason |
| **3b** Find Similar (was "duplicate finder") | **Built** 2026-09-22: Delete by context, Group/Show Similar, Keep One |
| **4** Setlist export / import | **Planned** 2026-09-22; **4a core export built**; next 4b core import |
| 5 Live desktop | Not started |

Library schema is now **version 12**. Every upgrade is additive and tested
by opening a library of the version before (7 rows, 8 music, 9 markers,
10 editing state, 11 rhythm patterns, 12 their note length). Jason's real
library steps up to 12 the first time a current build opens it. Before an
upgrade, the database is copied to `Library.sqlite.v<N>.bak`, named for
the version it was at. 154 core tests.

## Phase 3, as built (2026-09-21, fourth session)

The decisions are all in `spec/plan.md`, Phase 3. What was built, step by
step (one commit each, plus follow-ups):

1. **Modular rows** (`1b681fc`). Each show keeps its timeline rows
   (images, transitions, slides, music) in its own order (`Show.rows`).
   Every row has a handle pinned in the storyline's left margin: drag to
   reorder (undoable), click to slide its drawer out over the row, ⌥-click
   for all, Esc to close. The drawers only hold a name and icon so far;
   controls go in as features need them.
2. **The music row** (`9661eac`). Songs are library items of kind
   `.audio` (never slides or lane images; everything that adds items to a
   show filters with `model.pictures`/`model.songs`). Waveforms are read
   once per file and cached by hash in `<library>/Cache/Waveforms`.
   `MusicPlayer` schedules every song due from a moment on, on one
   AVAudioEngine, to start on the same sample, and while it plays **the
   show's clock reads the sound card's sample count** (`PlaybackClock.external`),
   so the picture follows what's heard. Music plays only forwards at
   normal speed; scrubbing and shuttling are silent. Anything that starts,
   stops or moves the clock must call `PlaybackEngine.syncMusic()`.
3. **Songs move, trim and crossfade; the level line** (`82d81d4`). Front
   trims move the in point with the start. Overlaps draw green; where one
   song starts inside another they crossfade at equal power
   (`AudioClip.gain`). `LevelLine` is one control for both song volume and
   lane-image opacity, with fade handles.
4. **The show is as long as its longest row** (`144e51a`). After the last
   slide the show's background colour shows (`FrameState.background`). A
   loop with time after the slides restarts with a cut, not a transition
   (`ShowTimeline.wrapsDirectly`). Images can go past the end. The show's
   default background got a colour well in the Edit Slides header bar.
5. **Markers, snapping, the range** (`dc79afb`, then `29beba2`). M drops a
   marker (`Show.markers`, undoable); N snaps slide cuts and image edges to
   markers; I/O set the range, ⌥X clears it, ⌘L loops playback in it.
   Jason's follow-ups: the markers' lines and the range's lines have
   separate transport switches; double-click one marker or range end for
   its own line, ⌥-double-click for every one of that kind. **The range,
   loop and line switches are the show's editing state (`Show.editor`),
   saved with the show so it opens as it was left, and never undone:** any
   undo keeps the editing state as it is now (`AppModel.update`). Marker
   edits, a marker's own line included, are undoable.

Everything above was checked by hand in a scratch library with `axtool`,
and measured where it could be. Two things only Jason can confirm: that
the music actually **sounds** right (fades, crossfades, sync with
Bluetooth headphones), and that the handles and drawers feel right.

## Starting step 6: beat detection

**Tested on macOS 27 (2026-09-22): all seven checks below pass.** The
first pass was written (Jason asked for it while
downloading macOS 27, 2026-09-21; commit after `20cde76`). It follows
proposals 1–6 below, with one change: **"Fit slides to markers" starts at
the slide the range begins in and uses as many slides as there are
markers**, rather than re-cutting only the slides whose cuts were already
in the range (that would re-cut two slides for eight markers). Tell Jason.
- Core, tested (116 tests): `SongRhythm` (cached per hash as
  `<library>/Cache/Rhythm/<hash>.json`), `BeatPlan` (every N beats / N
  bars / about X seconds; ×2, ÷2; bar shift), `SlideFitting.fit`,
  `BeatDetection.preview/apply`, detected markers on `AudioClip.markers`
  in song time, `Show.detectedMarkers/updateMarker/removeMarkers`.
- App: `Rhythms` (weak-linked `MusicUnderstanding`; `LC_LOAD_WEAK_DYLIB`
  checked in the release binary), `BeatSheet` (from the music drawer's
  button and a song's context menu), `RhythmMarks` (beat/bar ticks and
  section bands on clips; double-click a section sets the range), teal
  detected markers on the ruler (select, drag, Delete, double-click line,
  snapping), a faint teal preview while the sheet is open.
- **Checked on macOS 26.6.2** (2026-09-21): the app launches (the
  framework is weakly linked), and the music drawer's Detect Beats… button
  opens the sheet. The sheet says beat detection needs macOS 27 and names
  the Mac's version. Before macOS 27 it has **one button, "Bummer"**
  (Jason's wording), which closes it. Esc should also close it (a hidden
  cancel shortcut), but that went **untested**: Jason's VS Code came to the
  front mid-check and axtool rightly refused.
- **Test next, on macOS 27, in order:**
  1. The sheet shows Cancel and Apply, not Bummer.
  2. A song gets analysed: the 120 BPM click track should give beats
     every 0.5 s. Does it find bars, and any sections? Look at
     `<library>/Cache/Rhythm/<hash>.json`. An analysis that fails shows
     "Couldn't read the beats" with a Try Again button.
  3. Beat and bar ticks and section bands are drawn on the song clip.
  4. The sheet: its preview (faint teal markers on the ruler), the marker
     count, Apply, and one ⌘Z undoing it all.
  5. Fit slides.
  6. Teal markers: drag, Delete, double-click for the line, snapping to
     them, and moving the song carrying them.
  7. Double-clicking a section sets the range.

  Never run on the real library.

**Decided (Jason, 2026-09-21):** use **Apple's Music Understanding
framework** (WWDC26). It needs macOS 27. Our own detector (Accelerate,
spectral flux) was considered and turned down, so don't build a fallback.

**What the framework gives** (read from the macOS 27 SDK's
`MusicUnderstanding.swiftinterface` on this Mac, 2026-09-21; check it again,
since it was a beta SDK):
- `MusicUnderstandingSession(asset:)` (async throws), or
  `init(audioProvider:)` for streamed buffers. Then
  `analyze(for: [.rhythm, .structure, …])` returns a `SessionResult`.
  It's an actor, and `cancel()` exists.
- `RhythmResult`: `beats: [CMTime]`, `bars: [CMTime]` (the bar starts, i.e.
  downbeats), `beatsPerMinute: Float?`.
- `StructureResult`: `sections`, `segments`, `phrases`, each `[CMTimeRange]`.
- Also `key`, `pace`, `loudness` (integrated, momentary, short-term, peak),
  and `instrumentActivity`. Not needed yet.
- Everything is `@available(macOS 27.0, *)`. The deployment target is
  macOS 14, so wrap it in `if #available` and show a note in the apply
  sheet on older systems.
- The WWDC session says to create the `AVURLAsset` with
  `AVURLAssetPreferPreciseDurationAndTimingKey: true`.

**Agreed by Jason on 2026-09-22, as built.** "Start here" has the two
changes, and point 4 below describes the old version:
1. **Analyse each song automatically** when it's added, in the background,
   and cache the result per file by hash (like the waveform, e.g.
   `<library>/Cache/Rhythm/<hash>.json`, since the result types are
   Codable). Markers appear only when he applies.
2. **On song clips:** faint ticks for every beat and stronger ones for bar
   starts, plus the song's sections as bands along the clip.
   **Double-clicking a section sets the range to it**, a quick way to say
   "do the chorus like this".
3. **The apply sheet:** opened from a "Detect Beats…" button in the music
   row's drawer, and from a song's right-click menu. It applies to the
   range, or to the whole song with no range; if several songs fall in the
   range, each gets its own markers. The modes are "every N beats" (1, 2
   or 4, or once per bar) and "about every X seconds, landing on the
   nearest beat". Step 7 adds the rhythm patterns as a third mode, so
   leave room for it. A **live preview** of the markers shows faintly on
   the timeline while the settings change.
4. **"Fit slides to markers"** (a switch, already agreed in the plan):
   as built, from the slide the range starts in, each slide is resized to
   end on the next marker. Slides are never split. What follows
   ripples. Extra markers stay; slides with no marker left keep their
   lengths. Transitions stay centred on their cuts. The whole apply is one
   undo step.
5. **Detected markers:** teal, to tell them from the orange hand markers.
   They belong to their song, stored in song time on the `AudioClip`, so
   they move with it and hide when a trim cuts past them (they aren't
   deleted). They can be dragged or deleted one by one. Running it again
   on a range replaces that song's detected markers there, and never
   touches hand markers. Snapping uses both kinds.
6. **When the tempo is wrong** (usually out by a factor of two): **×2 / ÷2**
   (half-beats between, or every other beat) and **"bar starts here"**
   (shift the downbeat by a beat), in place of the plan's tap tempo, unless
   detection turns out to need it.

**Step 7 (after 6):** the rhythm patterns. They come in three
interchangeable forms: text (`w w h h q q 3e 3e 3e`, repeated to fill the
range), musical notation with note buttons, and a drum-machine step grid.
There's also a multiplier for how many beats a whole note stands for. All
of it is in the plan.

**Then the end of Phase 3:** settle image stickiness with Jason (below).

## Step 7: agreed, build order proposed (2026-09-22)

Every decision is in `spec/plan.md` under "Rhythm patterns" (Jason answered
the last five: yes to each). Proposed steps, one commit each, and "go
ahead with 7x" from Jason before each one:
- **7a Core, no UI: BUILT** (2026-09-22). `Sources/ShowToolsCore/Rhythm.swift`:
  `RhythmPattern` (the letters both ways; saved as its text; unreadable
  letters skipped and reported by offset, for the text field to mark),
  `RhythmPulse` (an even BPM, or a song's detected beats in show time,
  tempo-corrected), `RhythmPlacement.markers` (from the range start, or on
  a song its first beat at or after it; repeats; last pass cut short; stops
  where a song's beats do), `RhythmApply.apply` (orange hand markers, none
  doubled, plus Fit slides; one edit). 13 tests in `RhythmTests`, 130 in all.
- **7b The Rhythm panel, text only: BUILT** (2026-09-22). `RhythmPanel.swift`.
  Opens with ⌘R (Show menu) or "Rhythm…" in the slides row's drawer; first
  time at the bottom right, then where it was left. Follows the show on
  screen. Pattern field (unreadable letters named under it), a legend of
  Bravura glyphs that add letters, BPM (from the song's analysis; typing
  one gives an even beat, "Use the song's beats" goes back), "A quarter
  note =", Fit slides, marker count, Apply (orange hand markers, one undo,
  ⌘Z works with the panel in front). Faint orange preview on the ruler.
  Checked in a scratch copy: legend, 60 BPM (5 markers, times checked),
  Apply + ⌘Z, back to the song's beats, close, drawer.
  **Bravura came forward from 7c:** no macOS font has the Unicode music
  symbols, so the legend showed "?" boxes. Licence checked (OFL 1.1, bundle
  with the licence), `Resources/Fonts/`.
  Not done: the song choice is the one playing at the range start; the
  panel uses the detected tempo as is (×2/÷2 live in Detect Beats, 7e).
- **7c Notation: BUILT** (2026-09-22). Layout in the core
  (`RhythmNotation.layout`: x in staff spaces, beams within each beat,
  triplets in threes, a bar line every 4 quarters where a note ends on
  it, none across a note), 5 tests. Drawn by `RhythmNotationView` from
  Bravura's glyph outlines through Core Text (a `Text` would be placed by
  the font's huge line box), with Bravura's own stem/beam/bar thicknesses
  and anchors. Sixteenths get a second beam or a stub; triplets a 3, with
  a bracket unless one beam holds them; a closing repeat sign. It scrolls
  sideways and starts at the end, where notes are added. Checked by eye in
  a scratch copy with every feature in one pattern. The staff space is
  5.5 pt: ask Jason whether it should be bigger.
- **7d The grid: BUILT** (2026-09-22). `RhythmGrid` (core, 5 tests): a
  pattern on 16 steps a bar (straight) or 12 (triplet), nil when it fits
  neither; back to letters with each gap one note, as long as fits, and
  rests making up the odd lengths (5 sixteenths = `q rs`). `RhythmGridView`:
  Notes | Grid switch in the panel (remembered); in Grid the text field,
  notation and legend are hidden. A row per bar, beats spaced, the first
  square of a beat a shade lighter; click to light or clear; Straight /
  Triplet (refuses with a note if a lit square falls between the new
  steps); 1–8 bars. The feel last chosen is tried first, so an empty
  triplet grid stays triplet. Checked in a scratch copy.
- **7e Detect Beats' Pattern mode: BUILT** (2026-09-22). `BeatPlan.Mode.pattern`
  (core, tested): the song's detected beats with ×2/÷2, starting on the
  first bar start in the range after "bar starts" (the Rhythm panel starts
  at the range start instead; Detect Beats knows the bars). The sheet's
  Markers menu has Pattern: the letters, "A quarter note =", and Edit…,
  which opens the Rhythm panel in an editing mode (the pattern and Done,
  no Apply). Pattern and note length are shared with the panel
  (`rhythmPattern`, `rhythmQuarter`), so the sheet follows edits live.
  Closing the sheet closes a panel it opened, and returns one that was
  already open to normal. Checked in a scratch copy on Aerial
  Boundaries: `q e e` gave 13 teal markers, each on a detected bar or
  beat; one ⌘Z.
- **Grid spelling settled** (`e3c5740`): a note never runs past its bar
  line; rests fill the rest, split at bar lines (`q rw`).
- **7f Saved patterns: BUILT** (2026-09-22). **Schema 11**: a
  `rhythm_patterns` table (name unique, the pattern's letters); migration
  tested from a version-10 library, and the older rollback tests now drop
  the table too. Jason's real library upgrades the first time this build
  opens it, after a `Library.sqlite.v10.bak` copy. Built-ins in
  `RhythmPattern.builtIns`: Steady `q`, Long, short, short `h q q`, Build,
  Swing (triplet feel) `3q 3e`. The panel's **Patterns** menu (also in the
  editing mode for Detect Beats): built-ins, saved ones, Save Pattern…
  (a name; the same name replaces), Delete Saved Pattern (asks first).
  Checked in a scratch copy. **Schema 12** (Jason: keep the setting too):
  a saved pattern keeps its "a quarter note =" (`beats_per_quarter`, NULL
  for ones saved before, which leave the setting alone); picking it
  restores the setting; the menu shows "(q = 2 beats)". Built-ins leave
  the setting as it is.
- **7g Listen: BUILT** (2026-09-22). The Rhythm panel's Listen / Stop.
  `MusicPlayer.start` takes click times: a generated 25 ms 1.6 kHz tick on
  its own node, scheduled on the same engine and started on the same
  host time as the songs (works with no song too). `PlaybackEngine.listen`
  has its own loop over the range (the show's saved loop switch isn't
  touched); a new preview while listening takes effect next pass; playback
  stopping any other way ends it (`onListenEnded`). **Measured**: a
  recording tap (removed) over the click track, pattern `q` at 1 beat:
  every click within 2.2 ms of the song's (mean 1.2, at 0.7 ms
  resolution), gaps steady through the loop wrap. Not yet checked: Space
  stopping Listen resets the button (the code path is there); Jason's
  ears on real music.

## Still needs Jason's hands
- **The Rhythm tool** (step 7): the panel's look (the space around the
  form, the notation's size: a staff space is 5.5 pt), Listen by ear on
  real music, Space stopping Listen, and whether 145 BPM is right for
  Fly Me to the Moon (or double).
- **Listening:** music sync, fades, crossfades; Bluetooth headphones'
  delay (the output latency is subtracted, but it's untested).
- **Dragging a song in from Finder or Music.**
- **Look and feel:** the row handles (10 pt wide), the drawers, the level
  line's handles, whether a line on every clip is too busy in the thin
  images row, and the transport's new toggles.
- **From before Phase 3:** cross-app drags from Finder and Photos, Touch ID
  and the Mac's password, pinch, a second screen, cursors, and one real ⌘Z
  with the Info panel focused.

## How to work on it

```sh
swift test                                  # 108 core tests
./make-app.sh                               # → build/ShowTools.app
tools/make-test-library.sh <scratch>/STTest # scratch library + generated media
open -n --env SHOWTOOLS_LIBRARY=<scratch>/STTest/TestLib.noindex build/ShowTools.app
```
- **Never** run against the real library. Always set `SHOWTOOLS_LIBRARY`.
- Dev hooks are listed in `CLAUDE.md` (show, slide, image, rotation mode, transition, lane image, play).
- **A test song:** a click on every beat makes timing checkable by eye and by ear. Generate a WAV with Python's `wave` module (the session used 120 BPM: a 1 kHz click every 0.5 s over a quiet 220 Hz tone), `afconvert -f m4af -d aac` it to AAC, then `stcli ingest <lib> <file>`. `stcli ingest` doesn't add to a collection: add a `collection_items` row with `sqlite3` so the song shows in the collection list.
- **Seed show data** (markers, songs, image clips) straight into the scratch database with `sqlite3`, **with the app quit**. The app only reads the database when it loads, and a column a new build adds doesn't exist until that build has opened the library once.
- **Checking audio without ears:** a temporary tap on `engine.mainMixerNode` writing peak levels against the show clock to a scratch file. **Never call `DispatchQueue.main.sync` from the tap block:** when the engine stops on the main thread, each waits on the other and the app hangs on quit (it happened; the copy needed `kill -9`). Read the clock with a lock, or log the tap's own sample time instead. Remove the tap before committing.
- Screenshots: `swiftc tools/list-windows.swift` gives window ids, then `screencapture -x -o -l <id>`. `tools/contact-sheet.swift` tiles a folder of PNGs.
- **Get click coordinates from `ax find`/`ax dump`**, never from a screenshot. Check the element is on screen first: at a high zoom a marker can sit past the window's edge, and axtool refuses the click (⇧Z fits the show).
- `axtool click` takes `right|double|cmd|shift|opt|opt-double`. `opt` holds the Option key down, which is what `NSEvent.modifierFlags` reads.
- Frames: `stcli render <lib> <showID> 960x540 <outdir> <t>…` draws through the real Compositor. It prints each frame's state, `background after #N` included.
- Close test copies with `kill` or ⌘Q, not `kill -9`. **Check `pgrep -f ShowTools.app/Contents/MacOS` after a kill:** a copy that didn't quit means two copies on one scratch library.
- `defaults write com.jhg.showtools editMode show` and the `snapping` switch are Jason's **real** app preferences (a scratch library doesn't change the preferences domain). Leave them as found.
- Don't shell out to `osascript`/Finder for anything `ls`/`sqlite3`/`xattr` can already answer.
- **Tell Jason before restarting the app.** He often has it open and is trying things.

## Ask Jason later
- **Image stickiness (2c)**, now at the end of Phase 3: should a lane image stay at its time on the clock, or move with the slide it starts over when slides are trimmed or reordered? For now it stays on the clock.
- **A video slide's own sound**: muted for now. The idea is a volume line along the slide, so part of a clip can be kept (someone speaking) and part dropped (dogs barking). Punted until his first show.

## Known issues / debts
- **The Edit Slides header bar overflows** (Jason, 2026-09-21: address later). It scrolls sideways, and at normal window widths Background, Loop and "Videos play in full" sit past its right edge, out of sight. Options: wrap to two lines, or move the overflow into a menu.
- **A song lying wholly inside another** plays over it without crossfading (only a partial overlap crossfades). Level tops out at 100%.
- **The last slide cuts to the background** when something runs past the slides; a fade could come later.
- **The row drawers hold no controls yet.** Scrub audio (a music-row toggle, plan) isn't built; scrubbing is silent.
- **CPU** is about 33–37% while playing. This needs work before Phase 5's desktop mode.
- Memory is about 430 MB while playing.
- **Video:** it can't go in the lane yet. The frame strip shows a video's first frame. The onion skin skips video slides.
- The zoomed-out work area doesn't draw a lane image's overhang past the frame.
- Inspector sliders have no live preview while dragging; they update on release.
- Accordion was dropped, and Page Curl is offered as "Page Turn".

## Lessons (details in memory)
- **`PlaybackEngine.show` is `@ObservationIgnored`.** A view that reads it doesn't redraw when the show changes, so read the saved `show` that SwiftUI observes. The preview's image bar read the engine's copy and went stale, a bug that only showed once a second control could change opacity.
- **Undo restores a whole-show snapshot.** Anything that lives in `Show` but shouldn't be undone (the editing state) has to be carried over explicitly when undoing, as `AppModel.update` now does.
- **A new column breaks the older-version tests.** Each "a version-N library upgrades" test fakes an old library by dropping columns, so every newer column must be dropped too (the tests now chain `DROP COLUMN`s).
- **Driving the Mac's UI is driving Jason's Mac.** Events go to whatever is in front. axtool refuses unless ShowTools is frontmost, and refuses a crash-relaunch that dropped its scratch-library environment.
- **Synthetic clicks (and synthetic key events) aren't proof of a bug, or of a fix.** Settle a disagreement with a harness or, failing that, one real keypress/click from Jason.
- **Harnesses first for AppKit questions.**
- **Test the tests.** A new test should be run against the old code first, and fail there.
- **Measure with probes**, written to a file. `log show` returns nothing from this app in Claude's sandbox.
- **Swift decoding traps:** every model type saved as JSON decodes field by field, never synthesized `Codable`.
- **A separate window's `\.undoManager` isn't the presenting window's**, and the *key* window's own `undoManager` is what ⌘Z asks. Full write-up in `spec/macos_panels_guide.md` (in `jhg-cutcheck`).
