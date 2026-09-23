# ShowTools — status

**Read this first each session.** The state of play, in the present tense.
Rules are in `CLAUDE.md`, decisions in `spec/plan.md`, and what happened on
which day in `spec/history/` (never read for current rules). This file is
rewritten, not appended to: if a line has a date and a story, it belongs in
`history/`.

Repo: `~/Projects/ShowTools`, pushed to **github.com/JasonHunt3r/jhg-showtools**
(public, `main`).

## Where it stands

**Everything planned is built.** Phases 1–5, Phase 3b, Phase 4 and video
export. **279 tests** (267 core + 12 BGTools). **Library schema 12.**

| Phase | State |
|---|---|
| 1 Library + player | Built |
| 2 Composer (Edit Slides / Edit Show) | Built |
| 2a Framing, rotation, match cuts | Built, except presets (Flush), deferred |
| 2b Library manager | Built |
| 2c The lane: transitions row + images row | Built |
| 3 Music + timeline | All 7 steps built. Left: settle image stickiness |
| 3b Find Similar | Built: Delete by context, Group/Show Similar, Keep One |
| 4 Setlist export / import | Built, 4a–4d |
| E Video export | Built, E1–E5. Own spec `spec/video-export.md`. Left: a listen |
| 5 BGTools | Built, B1–B7. Own spec `spec/bgtools.md`. Left: Jason's hands-on pass; the Pan and Zoom cost; telling BGTools when a library moves |

Every schema upgrade is additive and tested by opening a library of the
version before (7 rows, 8 music, 9 markers, 10 editing state, 11 rhythm
patterns, 12 their note length). Before an upgrade the database is copied
to `Library.sqlite.v<N>.bak`. Video export needed no schema change: a video
slide's level line is slide settings, which are JSON.

`~/Applications/ShowTools.app` is built and installed from HEAD.

## What's next

1. **A listen, twice over.** (1) An exported movie against the same show
   playing: timing, crossfades, a video slide's sound against a song.
   (2) A video slide's sound in the app (V6): a clip with its middle
   dropped, a video against a song (they should just mix, no ducking),
   and whether the level glides or steps audibly — live it is set once
   per drawn frame, in an export per sample, so the export may be the
   smoother of the two.
2. **A show made from Jason's own photos and music**, imported by hand.
   This is what v1 end-to-end still needs. The demo show was seeded by a
   script, so ingest-by-drag, building a show by hand and editing it are
   untested by a person.
3. **Telling BGTools when a library moves** (B7 left it open).

**Ken Burns → "Pan and Zoom" — done 2026-09-23** (`8db7ffc`, `a0be113`),
in the UI, the code, the slide-settings JSON keys (`panAndZoom`,
`panAndZoomSeed`) and the setlist TSV columns (`panzoom_*`). No old
spelling was kept readable. The show-level default was already `.off`;
BGTools' random-mode default was the one place still `.auto`, now `.off`
too. `~/Applications/ShowTools.app` is rebuilt and reinstalled from HEAD.
**A setlist folder or `show.json` exported before this date will lose its
Pan and Zoom setting, silently, on re-import** — confirmed by hand
against a real export. Full story: `spec/history/2026-09-23-pan-and-zoom-rename.md`.

Parked: image stickiness, a guided first run (`spec/first-run-brief.md`),
and Flush presets from 2a.

## Still needs Jason's hands

- **The Rhythm tool** (step 7): the panel's look (the space around the
  form, the notation's size: a staff space is 5.5 pt), Listen by ear on
  real music, Space stopping Listen, and whether 145 BPM is right for
  Fly Me to the Moon (or double).
- **Listening:** music sync, fades, crossfades; Bluetooth headphones'
  delay (the output latency is subtracted, but it's untested).
- **Inspector sliders' live preview** — built (`b66b4af`) but never
  watched by eye; the commit says so.
- **Dragging a song in from Finder or Music.**
- **Look and feel:** the row handles (10 pt wide), the drawers, the level
  line's handles, whether a line on every clip is too busy in the thin
  images row, and the transport's new toggles.
- **BGTools:** unlocking a private library with Touch ID, the panel
  closing on a click elsewhere, Space-switch pausing — not yet re-done
  against the nested BGTools.
- **From before Phase 3:** cross-app drags from Finder and Photos, Touch
  ID and the Mac's password, pinch, a second screen, cursors, and one
  real ⌘Z with the Info panel focused.

## Open questions

- **Image stickiness (2c)**, at the end of Phase 3: should a lane image
  stay at its time on the clock, or move with the slide it starts over
  when slides are trimmed or reordered? For now it stays on the clock.
- **A simple way in.** The editor is detailed on purpose, which makes a
  plain slideshow harder than it should be (Jason, 2026-09-22). Raised,
  not designed.

## Known issues

- **An intermittent crash, at launch and on entering Edit Show.**
  `NSGenericException` from AppKit's layout-loop guard: a window marked as
  needing another Update Constraints pass more times than it has views.
  The loop is
  `SplitViewChildController.hostingView(_:didUpdateMinSize:maxSize:)` →
  `enqueueLayoutInvalidation` → `setNeedsUpdateConstraints`, so something
  in a split column reports a new minimum size *during* the constraints
  pass. **Which** column is unproven: `MainView`'s sidebar carries a
  `.safeAreaInset(edge: .bottom)` and truncating rows, either of which
  could do it, and neither has been shown to. It belongs to no one build
  (six crashed, matched by UUID) and `ViewThatFits` is cleared — the first
  crash predates it being added. **The
  exception is raised far more often than it kills the app, so count
  entries in `~/Library/Logs/ShowTools-exception.log`, not deaths** — and
  the bursts are real, so no run of trials proves anything. Full write-up:
  `spec/history/2026-09-23-crash-hunt.md`.
  **New repro and a corrected suspect, 2026-09-23 (later the same day):**
  it also fires switching Edit Show ↔ Edit Slides mid-session, not only at
  launch, and on this occasion the columns were pushed off-window when it
  happened (fits the divider entry below, not proven). The fatal stack's
  frame 27 names the exact class: `SplitViewChildController
  .hostingView(_:didUpdateMinSize:maxSize:)`. **That class belongs to
  SwiftUI's own split-column machinery** (`NavigationSplitView` columns
  and the `.inspector()` column) — **not** to `ColumnsSplitView`
  (`ColumnsSplitView.swift`), which is a hand-rolled `NSSplitView` with
  plain frame-based `NSHostingView` children and goes through none of
  SwiftUI's split-column code at all. A first attempt at a fix moved
  `ShowView`'s `.inspector()` modifier so it mounts only with
  `EditSlidesView`, on the theory that flipping its `isPresented` in the
  same transaction as swapping the whole mode was the trigger (commit
  pending review). **It did not hold**: stress-testing the fixed build
  (15 rapid mode toggles) crashed again with the identical
  `SplitViewChildController` stack, and the exception also fired on plain
  launches with no mode-switching at all. The better-supported suspect
  now is `MainView`'s outer `NavigationSplitView` **detail column**
  itself (`MainView.swift`, the `detail:` closure holding `ShowView`):
  its content changes type — `EditSlidesView`'s `List` versus
  `EditShowView`'s `NSViewRepresentable`/`VSplitView` tree — both the
  first time it mounts (launch, if `editMode` was left on `.show`) and
  every time the mode switch swaps it mid-session, which is exactly the
  "within 20s of launch, or on this one specific transition" pattern seen
  so far. Not proven either. Still unfixed.
- **Pulling the inspector's divider far to the left breaks the layout**
  ("smashes both sides out off the screen"). Seen once in a test copy
  dragging from the right edge to x=300. `revealByDragging` is the obvious
  suspect — it clamps the width it sets, but nothing re-checks the columns
  as a whole. Needs reproducing before anything is changed.
- **⌥⌘0 (Restore Default Layout) can raise the layout-loop exception**,
  and killed the app once. Each part alone raised nothing; only all three
  together did, and then stopped.
- **A song lying wholly inside another** plays over it without crossfading
  (only a partial overlap crossfades). Level tops out at 100%.
- **The last slide cuts to the background** when something runs past the
  slides; a fade could come later.
- **The row drawers hold no controls yet.** Scrub audio isn't built;
  scrubbing is silent.
- **CPU** is about 33–37% while the editor plays; memory about 430 MB.
  BGTools' desktop mode is ~2% since B6, except while Pan and Zoom moves,
  which costs about 40% of a core because it really does redraw every
  frame — worth a look. It's why BGTools' random-mode default was flipped
  to `.off` 2026-09-23 (it's opt-in now, not a cost every random desktop
  show pays).
- **Video:** it can't go in the lane yet. The frame strip shows a video's
  first frame, the onion skin skips video slides, and `stcli render` draws
  a video slide as the background colour — only `stcli movie` and the app
  go through `MovieMedia`. A video slide's sound is decoded whole into
  memory when exporting; fine for slides, worth revisiting if whole films
  ever become slides.
- The zoomed-out work area doesn't draw a lane image's overhang past the
  frame.
- Accordion was dropped, and Page Curl is offered as "Page Turn".

## Test things installed on Jason's Mac

`ShowTools.app` in `~/Applications` (the real one, with BGTools and the
tiles inside), `build/DesktopProbe.app` (not running), and XcodeGen
(`brew install xcodegen`, now required to build the app at all). Stale
Background Task Management entries for `com.jhg.bgtools` and two
`com.jhg.nestprobe` ids remain — `sfltool resetbtm` would clear them but
resets every app's login items, so they are left alone.

## Quick start

```sh
swift test                                  # 267 core + 12 BGTools tests
./make-app.sh                               # → build/ShowTools.app
tools/make-test-library.sh <scratch>/STTest # scratch library + generated media
open -n --env SHOWTOOLS_LIBRARY=<scratch>/STTest/TestLib.noindex build/ShowTools.app
```

Before launching any test copy, read the `showtools-testing` skill: a test
copy shares Jason's preferences domain, and a crashed one shuts his real
app out.
