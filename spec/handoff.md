# ShowTools — handoff, 2026-09-21 (end of the audit day)

For the next session. Read `CLAUDE.md` (rules) and `spec/plan.md` (every
decision, phase by phase) first. This file is the state of play. The repo
is `~/Projects/ShowTools`, pushed to **github.com/JasonHunt3r/jhg-showtools**
(public, `main`).

## Where it stands

| Phase | State |
|---|---|
| 1 Library + player | Built |
| 2 Composer (Edit Slides / Edit Show) | Built |
| **2a** Framing, rotation, match cuts | **Built**, except presets (Flush), which are deferred |
| **2c** The lane: transitions row + images row | **Built**, except the parked items below |
| **2b** Library manager | **Started**: Collections, libraries, import, grid and ratings are built; delete, rename, Info and relink are not |
| 3–5 | Not started |

Built this session (2026-09-21, day two):
- **2a:**
  - a **Transform** on every slide (position, zoom below 1×, rotation, anchor, background colour), with Fit now the default for new shows
  - **handles** on the preview (move, corner scale, Option for centre, rotate outside a corner, Shift snaps to 15°, anchor crosshair)
  - the **key map** (arrows 1/10 px; Option+←/→ rotate; Option+↑/↓ zoom; a run of presses is one undo step)
  - a **zoomable work area**, with the overhang dimmed
  - the **onion skin** (the previous slide's last frame)
  - the **soft-at-this-zoom** warning
  - **Rotation** (Angles or Speed, centre-zero acceleration, start/end pivots with a lock, freeze on transition) with its own on-picture **Rotation mode**, green start and red end
  - Ken Burns gains acceleration and freeze
- **2c, the lane:**
  - transitions carry a **lead** (they can start before their join)
  - a **transitions row**: sections across joins, draggable edges, a cut is an empty join with a +, and new shows default to a 2 s dissolve centred on the join
  - an **images row** (overlay clips on the show's clock): drop, place, move, trim, select with handles, and opacity, blend, fit and fades
- **2b:**
  - five-star **ratings** on files
  - **Library → Collection → Show** in the sidebar
  - the **Collection Browser** (the show's uses first, numbered and in order of appearance; then the rest; E/W/Q; dragging)
  - the **"isn't in the collection, add it?"** question, with its "Always add without asking" setting
  - **Import into a collection / Add to Library**
  - a Photos-style **Library grid** (search, filters, sort, drag)
  - **libraries**: open, new, recent, master, and **private** (Touch ID or password)
- **Inspector:** the slide, then **Effects** with a display-only timeline of what acts when.
- **Frame strip:** rendered frames of the finished picture under the picture, in the viewer column only, sized by a grabbable bar; follows the storyline or shows the whole show; ⌥⌘F.

### Audit and hands-on pass, 2026-09-21 (overnight, then the next day)

A full audit ran overnight (build and tests, a read of every file, dead
code, real-library safety, docs against code); the day after went on fixing
it and checking by hand. Everything is in `spec/audit-2026-09-21.md`, and
everything it found is fixed and pushed (commits after `2cbfce3`, up to `d4b67e7`):
- **High:** undo steps replayed into another library after a switch (ids
  restart at 1 in each); the grid kept the old library's thumbnails after a switch.
- **Medium:** short slides let two transitions overlap (measured); imports
  could run at once, and a failed one left a stray copy in `Media/`;
  J/K/L/space/⇧Z could eat typing in text fields; the show name saved on
  every keystroke.
- **Safety:** a launch with a `SHOWTOOLS_` variable but no
  `SHOWTOOLS_LIBRARY` opens nothing; a library is backed up
  (`Library.sqlite.v<N>.bak`) before any upgrade; and the first plain launch
  after a crashed test copy opens nothing (`TestLaunchRecord`), because the
  crash reporter's Reopen relaunches without the test's environment.
- **Low:** nine edge cases, and `KenBurnsFrame`, `ImagePoint` and `SRGBColor`
  now decode field by field.
- **Found during the hands-on pass, fixed:**
  - a **crash**: `ColumnsSplitView` was its own delegate, and asked about
    `toggleSidebar:` it recursed until the stack overflowed (seen twice, from
    Accessibility reads of the menus; proven in a harness)
  - **Collection Browser rows didn't select** on a click on their content, and
    a multi-row drag carried one file: `.onDrag` on List rows. Now `.itemProvider`.
    Double-click on a use toggles the inspector again (lost when the browser
    replaced the order list). Jason confirmed all three by hand.

**Claude can now click in the app.** Accessibility is granted to the Claude
app, and `tools/axtool.swift` reads the UI and sends real mouse and key
events (rules in CLAUDE.md). It drove eight of the audit's nine hands-on
checks; all nine pass.

Library schema is now **version 5**: 2 ratings, 3 overlays, 4 collections, 5 library settings. Every upgrade is additive and tested by opening the previous version. The master library upgrades itself the first time this build opens it.

### Confirmed by hand (Jason, or Claude with axtool)
- Moving and rotating an image with the handles saves correctly
- Zooming and rescaling with the mouse
- The frame strip's placement under the picture, its height limits, and the grabbable bar ("looks good")
- The inspector with the column fix restored ("cool")
- The inspector's Effects section and the frame strip's link menu
- Audit day: every audit check (see the audit file); Collection Browser rows
  select, double-click toggles the inspector, and a multi-row drag arrives
  whole (Jason); J/K/L, space and ⇧Z in Edit Show; renaming a show; File ▸
  Import… with its "Import into:" menu; File ▸ Open Library…, Open Recent and
  Open Master; Place Image Here… and its collection question; trimming a
  slide's end (Claude)

### Built but not yet tried by hand

**Most of this list was run by Claude on 2026-09-21: results in
`spec/hands-on-2026-09-21.md`.** What's left below is what it couldn't
reach (Finder/Photos drags, Touch ID, pinch, a second screen, cursors,
looks), plus Speed mode and the pivot lock (below the inspector's fold).
Everything below has only been seen in screenshots, or not at all. Claude
can now work through most of it with `tools/axtool.swift`; what still needs
Jason's hands is cross-app drags (Finder, Photos), Touch ID, pinch, a
second screen, and whether things look and feel right. Grouped so a test
pass can go area by area:
- **Handles and keys:** the cursor for each zone, corner scale with and without Option, Shift-snapped rotation, dragging the anchor, the arrow keys, ⌘Z undoing one drag or one run of nudges
- **Work area and onion skin:** the zoom menu and pinch, grabbing handles out in the margin, the onion toggle and its opacity
- **Rotation mode:** the Transform/Rotation switch, dragging each arm (going round twice should give 720°), Speed mode's red arm, the pivots locked and unlocked
- **Inspector sliders:** Transform, Rotation, acceleration, pivot pads, freeze. Each should be one undo step per drag, and the preview only updates on release
- **Transitions row:** dragging edges and the middle (snaps to centred), + at a cut, Delete on a selected transition (makes a cut, doesn't delete slides), the controls over the picture, Use Show Default
- **Images row:** it opening when dragged over, drops from Finder and Photos, right-click Place Image Here…, moving and trimming (no overlaps), selecting in the row and on the picture, its bar, Delete, Esc
- **Collections and browser:** + New, rename and delete (deleting a collection warns about its shows), a collection's grid, New Collection from Items / Add to / Remove from Collection, the browser's arrow, search and filters, E/W/Q, and a storyline selection highlighting its entry
- **Dragging:** browser rows onto the storyline (insertion line); grid tiles onto collections and shows; Finder and Photos files onto all of those; the add-to-collection question, its Cancel, and "Always add…" switching on the Settings preference
- **Import and grid:** File ▸ Add to Library…, the grid's search, filters and sort
- **Libraries:** New, Open Recent's never listing private libraries, Settings ▸ Private library (turning it off asks), Unlock on the locked screen, and the Spotlight setting with an alternate library open (it should rename *that* folder)
- **Frame strip:** Follow Storyline while scrolling and zooming, Whole Show, clicking a frame, ⌥⌘F
- **From Phase 2, still untried:** trimming a video's start, pinch on the storyline, the 1-second hover info, popping out the preview onto a second screen, dragging from the Photos app

## Next

0. **Fix the hands-on findings** (summary at the end of `spec/hands-on-2026-09-21.md`):
   - **Half-speed drags in the lane:** transition sections (edges, middle) and
     lane images (move, trim) follow the pointer at half speed. Their
     `DragGesture`s (StorylineView.swift `transitionDrag`, ImagesRow.swift
     `drag`) measure in the moving view's local space; use
     `coordinateSpace: .named("storyline")` like the trim edges. Recheck
     with axtool: 40 pt at 80 pt/s should give 0.5 s.
   - **Delete on a selected transition** does nothing while the keyboard is
     in the sidebar; clicking a section doesn't move it.
   - **Esc** doesn't deselect a lane image selected in its row (only the
     picture's overlay handles Esc).
   - Then check **Speed mode** and the **pivot lock** (scroll the inspector
     with `axtool scroll`).
1. **Suggested: a hands-on pass with Jason's own photos**, in a separate library (File ▸ New Library…) so the master isn't used. Claude can take most of the list above first with axtool, leaving Jason the parts that need hands and eyes; it also sets up the parked stickiness question.
2. **The rest of 2b:**
   - Delete the Photos way (Delete asks, ⌘Delete trashes, ⌘Z restores)
   - Finder-style batch rename
   - an Info panel (camera metadata, tags, the Finder-tags option)
   - relink by hash
   - Note: "which shows use this file" must count lane images (`shows.overlays` JSON), not just slides.
3. **Phase 3:** music and waveform. Then 3b duplicate finder, 4 setlist export, 5 live desktop.

## How to work on it

```sh
swift test                                  # 81 core tests
./make-app.sh                               # → build/ShowTools.app
tools/make-test-library.sh /tmp/STTest      # scratch library + generated media
open -n --env SHOWTOOLS_LIBRARY=/tmp/STTest/TestLib.noindex build/ShowTools.app
```
- **Never** run against the real library. Always set `SHOWTOOLS_LIBRARY`.
- Dev hooks are listed in `CLAUDE.md` (show, slide, image, rotation mode, transition, lane image, play).
- Screenshots: `swiftc tools/list-windows.swift` gives window ids, then `screencapture -x -o -l <id>`. `tools/contact-sheet.swift` tiles a folder of PNGs.
- Frames: `stcli render <lib> <showID> 960x540 <outdir> <t>…` draws through the real Compositor, lane images included.
- Driving the app: `swiftc -O tools/axtool.swift -o <scratch>/ax`, then `ax front <pid>`, `ax find <pid> <text>`, `ax click x y`, `ax type …`, `ax menu <pid> File "Import…"`. It refuses input unless ShowTools is frontmost. Read the UI with `find`/`dump` before taking screenshots. Close test copies with `kill` or ⌘Q, not `kill -9`.
- Reading the menus through Accessibility validates every item, like opening them; that's how the split-view crash surfaced. A crashed copy's crash dialog has a Reopen button: it launches without `SHOWTOOLS_LIBRARY` (now refused once, by design).
- **Tell Jason before restarting the app.** He often has it open and is trying things.

## Ask Jason later
- **Image stickiness (2c).** Once he has his own files as a test bed: should a lane image stay at its time on the clock, or move with the slide it starts over when slides are trimmed or reordered? For now it stays on the clock.

## Known issues / debts
- **CPU** is about 33–37% while playing. This needs work before Phase 5's desktop mode.
- Memory is about 430 MB while playing.
- **Video:** it can't go in the lane yet. The frame strip shows a video's first frame. The onion skin skips video slides.
- The zoomed-out work area doesn't draw a lane image's overhang past the frame.
- Inspector sliders have no live preview while dragging; they update on release.
- Accordion was dropped, and Page Curl is offered as "Page Turn".

## Lessons from the audit day (details in memory)
- **Driving the Mac's UI is driving Jason's Mac.** Events go to whatever is in front: typed paths landed in his editor once. axtool now refuses unless ShowTools is frontmost. A crash relaunch dropped the scratch-library environment and created an empty real library; that's guarded now too.
- **Synthetic clicks aren't proof of a bug, or of a fix.** Browser rows ignored every synthetic click, and Jason's real clicks found the pattern (only the edges selected). A harness with both versions side by side then settled it in one run.
- **Harnesses first for AppKit questions:** the self-delegating split view crashed in a ten-line harness on the first try, and the `.onDrag` vs `.itemProvider` harness answered select, ⌘-click, double-click and multi-drag at once.
- **Test the tests:** every new test was run against the old code first and failed there (the overlap test caught a second case nobody had found).

## Lessons from day two (details in memory)
- **When Jason reports breakage right after a layout change, that change is what he means.** "The inspector isn't opening and the list won't scroll", straight after the frame strip went in, meant "put the strip under the picture". I fixed a real but different bug, he said undo, the revert then went too far, and it was reapplied. Ask before fixing symptoms.
- **Measure with probes.** A frame and hit-test dump, written to a file, found the 28 pt inspector overhang in one run, after two wrong guesses. `log show` returns nothing from this app in Claude's sandbox, so write probes to a file.
- **SwiftUI hosting views hit-test all their content, clipped or not.** Hence `ColumnHost`, which refuses the mouse outside its own frame.
- **Swift decoding traps:** adding a field to a synthesized-Codable type (KenBurns, Transition) would have dropped every saved value. Every model type now decodes field by field.
- **More name collisions:** `RGBColor` (QuickDraw) became `SRGBColor`, and `Collection` (Swift) became `MediaCollection`.
- **Core Image mixes in linear light,** so a 50% mix encodes to about 0.735 sRGB. Tests expect that.
