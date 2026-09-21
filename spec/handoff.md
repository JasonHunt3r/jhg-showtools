# ShowTools — handoff, 2026-09-21 (evening)

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

Library schema is now **version 5**: 2 ratings, 3 overlays, 4 collections, 5 library settings. Every upgrade is additive and tested by opening the previous version. The master library upgrades itself the first time this build opens it.

### Confirmed by Jason this session
- Moving and rotating an image with the handles saves correctly
- Zooming and rescaling with the mouse
- The frame strip's placement under the picture, its height limits, and the grabbable bar ("looks good")
- The inspector with the column fix restored ("cool")
- The inspector's Effects section and the frame strip's link menu

### Built but not yet tried by hand
Everything below has only been seen in screenshots, or not at all where it
needs a mouse. Grouped so a test pass can go area by area:
- **Handles and keys:** the cursor for each zone, corner scale with and without Option, Shift-snapped rotation, dragging the anchor, the arrow keys, ⌘Z undoing one drag or one run of nudges
- **Work area and onion skin:** the zoom menu and pinch, grabbing handles out in the margin, the onion toggle and its opacity
- **Rotation mode:** the Transform/Rotation switch, dragging each arm (going round twice should give 720°), Speed mode's red arm, the pivots locked and unlocked
- **Inspector sliders:** Transform, Rotation, acceleration, pivot pads, freeze. Each should be one undo step per drag, and the preview only updates on release
- **Transitions row:** dragging edges and the middle (snaps to centred), + at a cut, Delete on a selected transition (makes a cut, doesn't delete slides), the controls over the picture, Use Show Default
- **Images row:** it opening when dragged over, drops from Finder and Photos, right-click Place Image Here…, moving and trimming (no overlaps), selecting in the row and on the picture, its bar, Delete, Esc
- **Collections and browser:** + New, rename and delete (deleting a collection warns about its shows), a collection's grid, New Collection from Items / Add to / Remove from Collection, the browser's arrow, search and filters, E/W/Q, clicking a numbered use, and a storyline selection highlighting its entry
- **Dragging:** browser rows (one and several) onto the storyline (insertion line) and the images row; grid tiles onto collections and shows; Finder and Photos files onto all of those; the add-to-collection question, its Cancel, and "Always add…" switching on the Settings preference
- **Import and grid:** File ▸ Import… and its "Import into:" menu, File ▸ Add to Library…, the grid's search, filters and sort
- **Libraries:** Open, New, Open Recent (private libraries never listed), Open Master, Settings ▸ Private library (turning it off asks), Unlock on the locked screen, and the Spotlight setting with an alternate library open (it should rename *that* folder)
- **Frame strip:** Follow Storyline while scrolling and zooming, Whole Show, clicking a frame, ⌥⌘F
- **From Phase 2, still untried:** trimming a video's start, J/K/L, pinch and ⇧Z on the storyline, the 1-second hover info, popping out the preview onto a second screen, dragging from the Photos app

## Next

1. **Suggested: a hands-on pass with Jason's own photos**, in a separate library (File ▸ New Library…) so the master isn't touched. It works through the list above and sets up the parked stickiness question.
2. **The rest of 2b:**
   - Delete the Photos way (Delete asks, ⌘Delete trashes, ⌘Z restores)
   - Finder-style batch rename
   - an Info panel (camera metadata, tags, the Finder-tags option)
   - relink by hash
   - Note: "which shows use this file" must count lane images (`shows.overlays` JSON), not just slides.
3. **Phase 3:** music and waveform. Then 3b duplicate finder, 4 setlist export, 5 live desktop.

## How to work on it

```sh
swift test                                  # 70 core tests
./make-app.sh                               # → build/ShowTools.app
tools/make-test-library.sh /tmp/STTest      # scratch library + generated media
open -n --env SHOWTOOLS_LIBRARY=/tmp/STTest/TestLib.noindex build/ShowTools.app
```
- **Never** run against the real library. Always set `SHOWTOOLS_LIBRARY`.
- Dev hooks are listed in `CLAUDE.md` (show, slide, image, rotation mode, transition, lane image, play).
- Screenshots: `swiftc tools/list-windows.swift` gives window ids, then `screencapture -x -o -l <id>`. `tools/contact-sheet.swift` tiles a folder of PNGs.
- Frames: `stcli render <lib> <showID> 960x540 <outdir> <t>…` draws through the real Compositor, lane images included.
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

## Lessons from this session (details in memory)
- **When Jason reports breakage right after a layout change, that change is what he means.** "The inspector isn't opening and the list won't scroll", straight after the frame strip went in, meant "put the strip under the picture". I fixed a real but different bug, he said undo, the revert then went too far, and it was reapplied. Ask before fixing symptoms.
- **Measure with probes.** A frame and hit-test dump, written to a file, found the 28 pt inspector overhang in one run, after two wrong guesses. `log show` returns nothing from this app in Claude's sandbox, so write probes to a file.
- **SwiftUI hosting views hit-test all their content, clipped or not.** Hence `ColumnHost`, which refuses the mouse outside its own frame.
- **Swift decoding traps:** adding a field to a synthesized-Codable type (KenBurns, Transition) would have dropped every saved value. Every model type now decodes field by field.
- **More name collisions:** `RGBColor` (QuickDraw) became `SRGBColor`, and `Collection` (Swift) became `MediaCollection`.
- **Core Image mixes in linear light,** so a 50% mix encodes to about 0.735 sRGB. Tests expect that.
