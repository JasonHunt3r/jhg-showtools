# ShowTools — handoff, 2026-09-21

For the next session. Read `CLAUDE.md` (rules) and `spec/plan.md` (every
decision, phase by phase) first; this file is the state of play.

## Where it stands

Phases 1 and 2 are **built and committed**, and so are four rounds of Phase 2
fixes from Jason's hands-on testing. The repo is `~/Projects/ShowTools`, pushed
to **github.com/JasonHunt3r/jhg-showtools** (public, `main`).

- **Phase 1:** the managed library (`~/Pictures/ShowTools Library.noindex`,
  SQLite plus copied, hash-verified media, hidden from Spotlight by default,
  with a Preferences toggle). Shows are built from the library. A player
  window, 13 transitions, and Ken Burns off/auto/custom.
- **Phase 2:** the **Edit Slides / Edit Show** modes. Edit Show has a large
  preview (with pop-out), a CutSim-style transport, and a Final Cut-style
  storyline: proportional widths, true-shape thumbnails, magnetic drag-reorder,
  and three grab zones per cut (trim end, roll, trim start, with `clipStart`
  for video). It also has an order list, a collapsible inspector, the Ken
  Burns frame editor, and undo for everything.

### Confirmed working by Jason
- Storyline drag-reorder (he reordered the test show)
- Column layout: the list's dividers resize only their neighbours, and
  dragging the inspector shut moves the list over
- Double-clicking a list item toggles the inspector
- No stale divider line after collapse

### Built but not yet tried by hand
I can't send clicks or keys on this Mac, so these have only been seen in
screenshots:
- the three cut zones, especially **trimming a video's start** (clip.mov)
- J/K/L shuttle, ⌘+/⌘−, pinch, ⇧Z fit, the 1-second hover info
- dragging the Ken Burns frames; ⌘Z / ⇧⌘Z
- popping out the preview onto a second screen
- **dragging from the Photos app** (the code path exists but has never been exercised)
- **Phase 2a inspector (2026-09-21), seen only in screenshots:** the Transform
  sliders (position, zoom, rotation), the background colour well, Rotation's
  sliders, Angles/Speed, acceleration, both pivot pads and their Lock,
  freeze on transition, and Ken Burns's new acceleration and freeze. Each
  slider should be one undo step per drag, and the preview only updates on
  release (no live preview while dragging yet)
- **Image handles and keys (2026-09-21):** Jason has dragged the image
  (a move and a rotate saved correctly). Not yet reported on: the cursors
  per zone, corner scaling with and without Option, Shift-snapped rotation,
  dragging the anchor, the arrow-key map, and ⌘Z undoing one drag or one
  run of nudges as a single step
- **Work area and onion skin (2026-09-21):** checked by screenshot only.
  Try the zoom menu (top left of the preview) and pinch; grabbing a handle
  out in the margin; the onion toggle and its opacity slider. The onion
  skin skips video slides for now (asking for another video's frame would
  seek its player)
- **Rotation mode (2026-09-21):** checked by screenshot (outlines and arms
  land where the maths says). Try: the Transform/Rotation switch, dragging
  each arm (Shift snaps to 15°; going round twice should give 720°), Speed
  mode's red arm setting the speed, and dragging the pivots, locked and not
- **Transitions row (2026-09-21):** checked by screenshot. Try: dragging a
  section's left and right edges and its middle (snaps to centred), the "+"
  on hover at a cut, Delete on a selected transition (should make a cut,
  not delete slides), the controls over the picture, and "Use Show Default"
- **Images row (2026-09-21):** checked by screenshot (two clips, fades
  drawn as ramps). Try: the row opening when an image is dragged over it;
  dropping from Finder and from Photos (lands where dropped, 5 s, half size,
  cut short by the next image); right-click → Place Image Here… and the
  library picker; dragging a clip and its edges (no overlaps); Delete on a
  selected image
- **Selecting a lane image (2026-09-21):** checked by screenshot (handles on
  the image, its bar over the picture). Try: clicking the image in the row
  (the playhead should jump onto it) and on the picture (the lane image wins
  over the slide under it); its handles and arrow keys; the opacity slider,
  blend mode, fit and fades; Esc and a background click to deselect
- **Collections sidebar (2026-09-21):** checked by screenshot (Library →
  Collections → shows nested). Try: + New ▸ New Collection / New Show; a
  collection's grid (select it); right-click Rename… and Delete… on both
  (deleting a collection warns how many shows go with it); dropping files
  on a collection; in a grid, New Collection from Items, Add to
  Collection, Remove from Collection
- **Collection Browser (2026-09-21):** checked by screenshot (bar, rows,
  orange used-lines, stars). Try: the arrow opening and closing the
  inspector; search; the filter menu (in / not in this show, minimum
  stars); E, W and Q with files selected (append; insert at the nearest
  join; place in the images row at the playhead) and their right-click
  equivalents. The top section lists uses: a file used twice has two
  numbered entries. Try clicking a use (should select that slide in the
  storyline with its own inspector, or that lane image with its bar) and
  selecting a slide in the storyline (its entry should highlight)
- **Dragging and the add-to-collection question (2026-09-21):** none of it
  can be triggered without a mouse, so all untried. Try: dragging browser
  rows (one, and a multi-selection) onto the storyline (an insertion line
  at the join) and onto the images row; dropping Finder or Photos files on
  the storyline, the images row, a show in the sidebar and a collection;
  a file from outside the show's collection (e.g. Library ▸ Add to Show)
  bringing up "…isn't in the collection … Add it?", its Cancel (nothing
  added), and "Always add without asking" switching on Settings ▸
  Collections ▸ "Add files to the collection automatically"
- **Importing and the Library grid (2026-09-21):** checked by screenshot
  (the bar). Try: File ▸ Import… with its "Import into:" menu (a
  collection, New Collection, Library Only) and File ▸ Add to Library…;
  the grid's search, filters (incl. Not in Any Collection) and sort;
  dragging a multi-selection onto a collection and onto a show
- **Libraries (2026-09-21):** the locked screen checked by screenshot (a
  private master opens locked, nothing of it showing). Try: File ▸ Open
  Library…, New Library… (makes a .noindex folder), Open Recent Library
  (private ones never listed), Open Master Library; Settings ▸ Library ▸
  Private library (off asks for Touch ID or the password); Unlock on the
  locked screen. Also that Settings ▸ Let Spotlight index the library, with
  an alternate library open, renames *that* library's folder in place
- **Effects timeline and frame strip (2026-09-21):** both checked by
  screenshot. Try: the strip's top edge (bigger frames, fewer of them), its
  Follow Storyline / Whole Show menu, scrolling and zooming the storyline
  (frames should move with the blocks), clicking a frame, and View ▸ Show
  Frame Strip (⌥⌘F)
- **Soft-at-this-zoom warning (2026-09-21):** checked by screenshot; the
  flags on the test library are all correct for a 2560×1664 screen

## Next: after 2c (the lane is built: transitions row and images row)

Left in 2c: image stickiness (parked, see "Ask Jason later"), video in the
lane (images only for now), and drawing a lane image's overhang in the zoomed
out work area. After 2c, per the plan: 2b library manager.

2c is settled at two picture layers (storyline plus one connected clip per slide), stored as a list. See `spec/plan.md`. The text below is the original 2c note.

Designed and approved in `spec/plan.md`: Final Cut's model, with **connected
clips** stacked above the storyline and attached to a slide, so they move and
trim with it. Each has opacity, position and scale, a blend mode, fade in and
out, and PNG/HEIC alpha. The renderer composites the storyline picture last, so
layers are an extra compositing step in `Compositor.compose`, not a rewrite.

**Open question to ask Jason first:** which uses matter most? Logos or
watermarks, frames or borders, title cards, picture-in-picture or collages,
free-form overlaps, textures or light leaks. That decides what's built first.

After 2c, per the plan: 2b library manager (delete conventions, batch rename,
Info panel with tags and Finder-tag checkbox), 3 music and waveform, 3b
duplicate finder, 4 setlist export (TSV), 5 live desktop.

## How to work on it

```sh
swift test                                  # 19 core tests
./make-app.sh                               # → build/ShowTools.app
tools/make-test-library.sh /tmp/STTest      # scratch library + generated media
open -n --env SHOWTOOLS_LIBRARY=/tmp/STTest/TestLib.noindex build/ShowTools.app
```
- **Never** run against the real library. Always set `SHOWTOOLS_LIBRARY`.
- Dev hooks: `SHOWTOOLS_DEV_SHOW="<showID>[:<slideIndex>]"` and
  `SHOWTOOLS_DEV_PLAY="<showID>:<index>[:full]"`. The mode comes from the
  `editMode` default. The inspector state comes from `inspectorShown`, and
  `defaults write com.jhg.showtools inspectorShown -bool false` toggles it
  **while the app is running**, which is how collapse and expand were tested.
- Screenshots: `swiftc tools/list-windows.swift` to get window ids, then
  `screencapture -x -o -l <id>`. `tools/contact-sheet.swift <dir> <out.png>`
  tiles a folder of PNGs so they can be read in one look.
- Transitions and framing: `stcli render <lib> <showID> 960x540 <outdir> <t>…`
  writes frames through the real Compositor.
- UI scripting and CGEvent input are blocked (no accessibility permission).
  Anything that needs a drag, Jason tests.

## Ask Jason later
- **Image stickiness** (Phase 2c): once he has his own files set up as a
  test bed, ask whether an image in the lane should stay at its time on the
  clock or move with the slide it starts over when slides are trimmed or
  reordered. For now it stays on the clock.

## Known issues / debts
- **CPU** is about 33–37% while a show plays (60 fps Core Image redraw of
  stills). Idle previews now stop drawing. This needs work before Phase 5's
  always-on desktop.
- Memory is about 430 MB playing (4 decoded images at 1.25× screen size).
- The order list truncates filenames when narrow. Jason can widen it.
- Accordion was dropped (it renders as a plain dissolve on this macOS), and
  Page Curl is offered as "Page Turn" (it renders flat).

## Lessons from this session (details in memory)
- In SwiftUI, modifiers on a `Group` apply to each child. A `Group`'s
  onDisappear shut down the engine it made way for. Use a `ZStack`.
- NSSplitViewController holding priorities make the lowest-priority column
  absorb *every* change, including other dividers' drags, and they can't be
  changed at runtime. Hence `ColumnsSplitView`'s manual layout.
- With a manual layout, NSSplitView's divider layers go stale. That was the
  black line. Found by dumping the layer tree, not by guessing.
- `LibraryItem` and `Transition` collide with SwiftUI names.
