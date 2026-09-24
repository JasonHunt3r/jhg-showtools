# ShowTools — status

**Read this first each session.** The state of play, in the present tense.
Rules are in `CLAUDE.md`, decisions in `spec/plan.md`, and what happened on
which day in `spec/history/` (never read for current rules). This file is
rewritten, not appended to: if a line has a date and a story, it belongs in
`history/`.

Repo: `~/Projects/ShowTools`, pushed to **github.com/JasonHunt3r/jhg-showtools**
(public, `main`).

## Where it stands

**Everything planned is built**, including Groups inside collections
(below). Phases 1–5, Phase 3b, Phase 4 and video export. **305 tests**
(293 core + 12 BGTools). **Library schema 13.**

| Phase | State |
|---|---|
| 1 Library + player | Built |
| 2 Composer (Edit Slides / Edit Show) | Built |
| 2a Framing, rotation, match cuts | Built, except presets (Flush), deferred |
| 2b Library manager | Built |
| 2c The lane: transitions row + images row | Built |
| 3 Music + timeline | All 7 steps built. Left: settle image stickiness |
| 3b Find Similar | Built: Delete by context, Find/Show Similar, Keep One, Keep as Group |
| Groups inside collections | Built 2026-09-24, Core through UI (`spec/plan.md`) |
| 4 Setlist export / import | Built, 4a–4d |
| E Video export | Built, E1–E5. Own spec `spec/video-export.md`. Left: a listen |
| 5 BGTools | Built, B1–B7. Own spec `spec/bgtools.md`. Left: Jason's hands-on pass; the Pan and Zoom cost; telling BGTools when a library moves |

Every schema upgrade is additive and tested by opening a library of the
version before (7 rows, 8 music, 9 markers, 10 editing state, 11 rhythm
patterns, 12 their note length, 13 groups). Before an upgrade the database is copied
to `Library.sqlite.v<N>.bak`. Video export needed no schema change: a video
slide's level line is slide settings, which are JSON.

`~/Applications/ShowTools.app` is **one commit behind HEAD** (built
2026-09-23; the Groups work above isn't installed there yet).
`build/ShowTools.app` is current. BGTools' desktop extension is running
from the installed copy, so reinstalling wasn't done without asking —
say when to swap it in.

**The real library was set aside 2026-09-24** (Jason's own call, mid this
session): `~/Pictures/ShowTools Library.noindex` is now
`~/Pictures/ShowTools Library (2026-09-24).noindex`, untouched. The next
plain launch of the real app creates a fresh, empty library at the
default path.

## What's next

### Work queue for the Mac (from the cloud session, 2026-09-24)

Everything below is on **`main`** (merged from the cloud session's branch,
`claude/cloud-clauding-4lij0h`, 2026-09-24). **Pull `main` first.** The cloud session keeps to docs while the
Mac session works, so there are no clashes; pull again whenever it
pushes. Read `spec/history/2026-09-24-cloud-planning-aar.md` for what
happened and why. Load `showtools-testing` before any test copy (the
preferences-domain rules).

1. **Build and test the two unbuilt code changes** — done 2026-09-24.
   `swift test` (279 tests, 0 failures) and `./make-app.sh` both pass
   clean off `main`.
   - `7c1613a` (audit G1) and `dcf47c2` (audio names) both compile and
     the app launches fine against a scratch library. The hands-on
     checks (drop two files on Edit Slides / a sidebar show / Add to
     Show and read the Undo wording; the Audio row's title, icon, filter
     and context-menu text) still need doing — synthetic axtool clicks on
     the toolbar's "Add to Show" menu button and a tile-to-sidebar drag
     didn't reliably reproduce a real click/drop in this session (the
     popup never opened; the drop registered no undo step), so this
     stays on the "still needs Jason's hands" list rather than counting
     as verified.
2. ~~**⌘A in the Library grid: top priority**~~ — done 2026-09-24 (audit
   A1). Joins Delete/⌘Delete in the grid's `SingleKeys` monitor rather
   than a menu item (simpler, and the same fix the grid's focus problem
   already got); selects every tile in `visible`. Checked with a real
   ⌘A: 11/11 tiles, and the Search field's own select-all still works.
3. ~~**The rest of batch 1**~~ — done 2026-09-24: the Delete key and
   ⌘Delete in the Library pane (D1), undo for Delete Show (D2) and Rename
   Collection (D3). Found and fixed a real crash along the way — see
   Known issues below.
4. **Batch 2 — done 2026-09-24:**
   - ~~naming first, nothing made until OK (H1)~~ — New Collection done
     everywhere it's made; New Show deliberately left for the settings
     panel (`spec/simple-things-fast.md`), not a throwaway dialog now.
   - ~~Import can choose audio (H3), and the "song" error text (H4)~~ —
     done.
   - ~~empty-state buttons (H2, the plain tier)~~ — done: an empty
     collection gets Import…/Add from Library…, an empty show (Edit
     Slides) gets Add from Collection…/Import…, both through a new
     `MultiItemPicker` sheet.
   - ~~context menus, the obvious parts (C1–C3)~~ — done: Remove Image, Remove
     Transition and Remove Marker, each the exact `mutate` call its
     Delete-key handler already used. **Not confirmed by a real
     click** — the storyline's canvas didn't give axtool usable
     coordinates; wants Jason's own right-click. The fuller menus (C4–C7)
     wait for the right-click conversation, as planned.
   - **Update from the right-click conversation (2026-09-24):** the
     Library pane's and the Library grid's menus are now **settled**
     (`spec/conventions.md` §3, "Progress", stops 1 and 2), so those
     rows (C6, and the tile menu) needn't wait: build them in full.
     Items whose feature isn't built yet (Play without a show, Play on
     Desktop) go in greyed out, per Jason. The other menus still wait.
5. ~~**Groups inside collections**~~ — done 2026-09-24, Core through UI,
   including nesting and cross-collection dragging added after the fact
   on Jason's ask. 291 tests (was 279 before this item). Full story in
   `spec/plan.md`, "Groups inside collections". Real dragging (group
   onto group, onto its own collection, onto another) still wants
   Jason's hands — built and reasoned about, not clicked.
6. ~~**Batch 4: selection logic in Core, with tests**~~ — done 2026-09-24.
   `GridSelection` (`Sources/ShowToolsCore/GridSelection.swift`): pure
   functions over the caller's own `selected`/`anchor`/`base`/`cursor` —
   `click`, `commandClick`, `shiftClick` (fixes B3 and E1: a ⇧-click
   selects the range from the anchor, *replacing* the previous ⇧-range,
   not adding to it), and `step` (the arrow-key index arithmetic for
   B2/E2 — ± the column count for ↑/↓ in a grid, ±1 for a plain list;
   not wired into either view yet, since B2 waits for the grid's keyboard
   batch and E2 waits on Jason's ↑/↓-vs-←/→ decision). 14 new tests,
   including B3's and E1's exact worked examples from the audit. Wired
   into the Library grid's and the storyline's `click(_:)`, replacing
   each one's own buggy `.formUnion` logic (only ever added) and, in the
   storyline, an anchor that was wrongly derived from "the first selected
   slide" each time rather than kept as its own state.
   `swift test` (305, was 291) and `./make-app.sh` clean; smoke-launched
   again, no crash. *Check* (per the plan): the tests pass; a real
   ⇧-click in the grid and the storyline still wants Jason's hands.
7. **The PaneKit harness** (`spec/panekit.md`, "The order", step 1): a
   standalone app in `tools/` with dummy content, checked on the Mac and
   felt by Jason.

Then: the right-click conversation (the plan at the end of
`spec/conventions.md`), the show session (`spec/windows.md`), and the
New Show panel (`spec/simple-things-fast.md`).

### Also next

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
4. **Expected Mac behaviour** — `spec/hig-audit.md` (audited from code
   2026-09-24; G1 fixed, unbuilt; the rest is the work queue above). Missing conventions: ⌘A, ⌘D, arrow keys
   and Quick Look in the grid; context menus on lane images, transitions
   and markers; Edit Show's commands in no menu; Edit Slides and Edit
   Show disagreeing. One real bug: **adding slides by a drop onto Edit
   Slides, a show in the Library pane or Add to Show can't be undone** (G1). Eight fix
   batches, least risky first; three decisions for Jason.

**Ken Burns → "Pan and Zoom" — done 2026-09-23** (`8db7ffc`, `a0be113`),
in the UI, the code, the slide-settings JSON keys (`panAndZoom`,
`panAndZoomSeed`) and the setlist TSV columns (`panzoom_*`). No old
spelling was kept readable. The show-level default was already `.off`;
BGTools' random-mode default was the one place still `.auto`, now `.off`
too. `~/Applications/ShowTools.app` is rebuilt and reinstalled from HEAD.
**A setlist folder or `show.json` exported before this date will lose its
Pan and Zoom setting, silently, on re-import** — confirmed by hand
against a real export. Full story: `spec/history/2026-09-23-pan-and-zoom-rename.md`.

**Pan and Zoom only zooms** (Jason, 2026-09-24): Auto is mostly a zoom,
and Custom's pan is two small frames to drag in the inspector. Wanted: a
direction, and aiming the zoom by clicking the image. In the plan, under
Later.

Parked: image stickiness, a guided first run (`spec/first-run-brief.md`),
and Flush presets from 2a.

**Next conversation: right-click menus,** area by area, with
`spec/anatomy.md` as the guide. The plan is at the end of
`spec/conventions.md`. Finish the other universals first.

## Still needs Jason's hands

- **Audit G1 and the audio-naming pass** (`7c1613a`, `dcf47c2`): both
  build and the app launches, but the hands-on checks weren't done this
  session — see the work queue above.
- **Context menus C1–C3** (Remove Image/Transition/Marker): build and
  test clean, but not confirmed by a real click — the storyline canvas
  resisted synthetic clicking this session.
- **Groups in the Library pane** (built 2026-09-24): drag-to-add from the
  grid and from Finder, nested folding, New Group naming, the delete
  notice's wording, the browser's group filter, and Keep as Group. Also
  new: **dragging a group onto another to nest it, onto its own
  collection to un-nest it, and onto a different collection**, with the
  "images will be added" notice and its suppression checkbox. All of it
  only smoke-tested (launch, no crash), not clicked by a person.
- **⇧-click in the Library grid and the storyline** (batch 4, built
  2026-09-24): `GridSelection`'s logic is unit-tested against the audit's
  own worked examples, but a real ⇧-click, ⇧-click, ⇧-click hasn't been
  tried by hand in either place.
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
- **Windows of their own** (`spec/windows.md`): which areas detach, the
  Slide Editor, the library panel and Show in Library. Jason answered six
  of seven questions 2026-09-24; what comes first is still open. Its prerequisite is moving a show's
  editing state out of the views, which the audit's menu work wants too.
- **Simple things fast** (`spec/simple-things-fast.md`; was "a simple
  way in"). The editor does a lot, but simple things aren't fast. There
  are three answers: the guided first run, playing a library or
  collection without building a show, and three levels (Basic, Advanced,
  "Bring it on!"). Four questions for Jason.

## Known issues

- **The layout-loop crash — fixed 2026-09-23.** `NSGenericException` from
  AppKit's layout-loop guard, on selecting a show or switching Edit Slides
  ↔ Edit Show. **Confirmed cause:** SwiftUI's `.inspector()` modifier on
  `ShowView`'s `.slides` case (`spec/history/2026-09-23-crash-hunt-session3.md`).
  **The fix, landed:** `spec/edit-slides-inspector-port.md` — Edit Slides'
  inspector is now ported onto the same hand-rolled `ColumnsSplitView`
  mechanism `EditShowView` already used (a new two-pane shape, main +
  inspector, no middle list column). Verified against a clean rebuild and
  the exact repro that crashed every prior build: a copy of the real
  library, "Trucks to the Future" selected, 32 rapid Edit Slides ↔ Edit
  Show toggles at ~0.4s pacing — zero new entries in
  `~/Library/Logs/ShowTools-exception.log` (6060 before and after), and
  the ported inspector opens/closes from the toolbar and by double-click
  and shows the right slide's settings. Full story:
  `spec/history/2026-09-23-crash-hunt.md`,
  `spec/history/2026-09-23-crash-hunt-session2.md`,
  `spec/history/2026-09-23-crash-hunt-session3.md` (the one with the
  actual cause).
  **The same guard fired again, in a new place, 2026-09-24:** a
  `SingleKeys` key monitor (audit D1) in `.background()` directly on the
  sidebar `List` — a real `NSTableView`, unlike the grid's plain
  `ScrollView` where the same technique is fine — crashed on undoing a
  show deletion (`ShowTools-2026-09-24-034845.ips`). Fixed by moving the
  monitor to `.background()` on the whole `NavigationSplitView` instead of
  the List; the exact repro (select a show, ⌘Delete, ⌘Z) no longer
  crashes. **Lesson: `.background(SingleKeys)` is safe on a plain
  SwiftUI container, not on a `List` or anything else AppKit backs with
  its own constraint-based layout** — worth checking before adding one to
  Edit Slides' or the storyline's own Lists for later audit items.
- **Pulling the inspector's divider far to the left breaks the layout**
  ("smashes both sides out off the screen"). Seen once in a test copy
  dragging from the right edge to x=300. `revealByDragging` is the obvious
  suspect — it clamps the width it sets, but nothing re-checks the columns
  as a whole. Needs reproducing before anything is changed.
- **⌥⌘0 (Restore Default Layout) raised the layout-loop exception once**,
  and killed the app, on 2026-09-23: *before* the cause was confirmed as
  SwiftUI's `.inspector()` and fixed. Not seen since the fix; probably that
  same crash. The Library pane was a suspect only by coincidence (Jason). Its
  known bugs are display bugs. `DefaultLayout` still skips the Library pane on
  that stale reasoning, which is worth retrying.
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
swift test                                  # 293 core + 12 BGTools tests
./make-app.sh                               # → build/ShowTools.app
tools/make-test-library.sh <scratch>/STTest # scratch library + generated media
open -n --env SHOWTOOLS_LIBRARY=<scratch>/STTest/TestLib.noindex build/ShowTools.app
```

Before launching any test copy, read the `showtools-testing` skill: a test
copy shares Jason's preferences domain, and a crashed one shuts his real
app out.
