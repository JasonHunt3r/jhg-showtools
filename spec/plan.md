# ShowTools — plan

Approved 2026-09-20.

## What it is

A slideshow composer and player for macOS. You get as much control as possible
over each slide: how long it shows, which transition it uses, its Pan and Zoom move,
and how it lines up with a music track. It plays full screen, in a window, or
live on the desktop of each attached monitor.

## What it is not (for now)

- Not a product. It's built for Jason's own Mac: no signing, no notarization,
  no App Store.
- Not a full video editor. Layering is in scope (Phase 2c); colour grading,
  audio mixing and *public* plugins are not. (Changed 2026-09-21: this line
  used to rule out multi-track compositing. The app does have internal seams
  for its own plugins; see "Plugin seam".)

---

## Stack

Built the same way as CutSim (see `jhg-cutcheck/spec/macos_panels_guide.md`):

- SwiftUI app with AppKit underneath. **Updated 2026-09-22:** the app is
  built by one Xcode project (XcodeGen, `project.yml`), which is what lets
  BGTools and its Control Center tiles nest inside the ShowTools bundle —
  see `spec/xcode-port.md`. The libraries, `stcli` and the tests stay
  SwiftPM, so `swift test` is unchanged. It was originally SwiftPM
  throughout, wrapped into a `.app` by a shell script.
- Floating side panels are `NSPanel` utility windows that snap together and
  remember where they were. The code pattern gets copied over from CutSim.
- Rendering uses Core Animation layers plus Core Image's built-in transition
  filters (dissolve, swipe, page curl, ripple, mod, bars, copy machine,
  flash, disintegrate…).
- Audio uses AVFoundation. The waveform is read from the file once and cached.

## Core data model

### Library

The app keeps one **library database** of everything it has ingested. This is
the pool that "all files" means everywhere in the app. Every show draws its
slides from the library.

**Privacy:** Spotlight indexes more than tags. It indexes filenames, the
metadata inside the image (camera, date, GPS), and text it recognises in the
picture itself. Keeping images out of Spotlight means excluding the library
folder, not just leaving tags off. A folder whose name ends in `.noindex` is
skipped by Spotlight, so **by default the library is hidden:**
`~/Pictures/ShowTools Library.noindex/`. The Preferences pane has a setting,
**"Let Spotlight index the library"**, that renames the folder without the
suffix (and back again). The database stores paths relative to the library
root, so the rename doesn't break anything. The `.noindex` behaviour must be
verified with `mdfind` before relying on it.

**Managed library: files are copied in.** Ingesting a file copies it into the
app's own library folder. The copy is checked against the original's hash
before the ingest reports success, so after that the original can be safely
deleted from wherever it was.

- **Location:** `~/Pictures/ShowTools Library.noindex/` (see Privacy). On this Mac, Desktop and
  Documents sync to iCloud Drive but `~/Pictures` does not, so the library
  stays local. If a library location is ever chosen inside an iCloud-synced
  folder, the app refuses it
- **Folders:** the library can be organised into folders. A folder in the app
  is a real folder inside the library, so Finder shows the same structure. The
  app owns this folder: rearranging it by hand in Finder is not supported
  (the hash-based relink can recover from it, but that's a repair, not a
  workflow)

Each **library item** records:
- its file inside the library, and its folder
- a content hash, used for exact duplicates and for re-finding moved files
- media type, pixel size, and duration for video and GIFs
- when it was ingested and where it came from, and which shows use it

A library item carries **no** slide settings. Length, transition and Pan and Zoom
belong to the slide (see below).

Storage is SQLite, which is built into macOS and handles tens of thousands of
rows without effort.

### Show

A **Show** contains:

- a **default slide length**
- an ordered list of **Slides**
- an optional **Music track**, plus markers placed on it

A **Slide** is one *use* of a library item in a show. The same item can appear
several times in one show and in any number of shows, and every appearance
keeps its own settings. Each **Slide** has:

| Field       | Notes |
|-------------|-------|
| media       | a reference to a library item |
| length      | *inherit default*, or a specific value. Video can also be "clip length" |
| transition  | style, duration and direction for the transition *into* this slide. *Inherit default* is allowed |
| Pan and Zoom   | off, or a start frame and end frame (position and zoom), plus easing |
| fit         | fill / fit / stretch. New shows default to **fit** (changed from fill 2026-09-21) |
| transform   | the still placement on top of fit: offset, scale, rotation, anchor (Final Cut's Transform). Always there; the identity leaves the image where fit puts it (added 2026-09-21) |

Every field that can inherit does so until it's overridden. Changing the show's
default updates every slide that hasn't been given its own value.

### Video-export hook (built in from day one) — PAID OFF 2026-09-22

All rendering goes through one function: **"what does the screen look like at
time *t*?"** That covers which slide(s) are on screen, how far the transition has
got, and where the Pan and Zoom frame is. The live player, the timeline scrubber and
the desktop mode all call it. A future video exporter calls it too, once per
frame, and writes the frames with `AVAssetWriter`. So adding export later is a
new menu item, not a rewrite.

Slides never keep their own timers. Time always comes from one clock, which is
the music when a track is loaded and the system clock when it isn't.

---

## Phases

### Phase 1: Library + player — BUILT 2026-09-21
- The library database, plus ingest: drag in files or folders of images,
  animated GIFs and videos (from Finder, or from Photos via file promises).
  Anything already in the library is recognised by its hash and not added twice
- Build a show from the library (Add to Show, New Show from Selection, or
  drop files onto a show)
- Play in a window or full screen, with per-slide lengths, transitions and
  Pan and Zoom (show default Off/Auto; per-slide Off/Auto)
- Keyboard: space, ← →, Home/End, type a number + ↩ to jump, F, Esc
- **Changed from the draft:** shows are stored in the library database, not
  as separate document files. They save on every edit. They need to be in
  one place anyway so that "random show" can find them all.
- **Not yet:** ⌘Z undo (comes with the Phase 2 composer), a custom Pan and Zoom
  frame editor, and a drag-and-drop from Photos tested by hand (the code
  path exists, but no one has tried an actual drag from the Photos app)
- **Transitions dropped:** Accordion. On this macOS, Core Image's accordion
  fold renders as a plain dissolve. Page Curl renders flat, so it's offered
  as "Page Turn" (darkened back, peels from the far edge)

### Phase 2: Composer — two modes — BUILT 2026-09-21
Decided 2026-09-21. Timelines follow Final Cut's conventions.

**Edit Slides** is the Phase 1 view: a detailed slide list and the inspector,
for ripping through slides and their details.

**Edit Show** is new:
```
┌──────────────────────────────────────────────────────┬─ Order ────────┐
│              [ large live preview ]         ⤢ pop out│ ▣ 1 beach.jpg  │
│   in-frame play toggle + per-slide progress line     │ ▣ 2 sunset.jpg │
│ ▶ ━━━━━━━━━━●━━━━━━━━━━━━━━━━━  0:42 / 12:10 scrubber │ ▣ 3 dog.jpg    │
│ ruler ·····|·····|·····|·····|                       │  drag to       │
│ [▐▌sunset 8s ][▐▌dog 4s][▐▌cliff 12s       ] storyline│  reorder       │
└──────────────────────────────────────────────────────┴────────────────┘
```
- **Preview:** the show plays large (drawn with the same renderer as the
  player). A livery-style play toggle sits in the frame, with a progress line
  that drains across each slide. **Pop out** moves the preview into its own
  window, for a second monitor or full screen, and it stays in sync.
- **Scrubber (CutSim transport):** play button, a slider across the whole
  show, and the time. Scrubbing plays transitions too.
- **Storyline (Final Cut-style):**
  - a block's width is the slide's length, on a zoomable pixels-per-second scale
  - blocks are all the same height, and each thumbnail sits at the image's
    true proportions, so portrait and landscape can be told apart at a glance
  - a still's thumbnail doesn't repeat across its block (repeating a still is
    noise); video shows frames across its block
  - a transition shows as a marker on the cut, as wide as the transition is long
  - **magnetic:** blocks always sit end to end. Dragging reorders (a
    multi-selection moves as a group) and the rest close up
  - **three grab zones on every cut** (Final Cut edits), each with its own
    cursor and a yellow bracket: left of the cut **trims the left clip's
    end**, on the cut **rolls** it (one clip grows as the other shrinks, so the
    total length stays the same), and right of the cut **trims the right
    clip's start**. For video, trimming a start skips into the clip
    (`clipStart`). A readout shows the change while you drag
  - layout (changed 2026-09-21): the transport and storyline run the full
    width along the bottom; the preview, order list and inspector sit above
    them in resizable columns. Double-click a slide, or press ⌥⌘I, to open
    the inspector
  - a playhead that follows the scrubber; click or drag the ruler to move it
  - zoom with ⌘+ / ⌘−, pinch, and ⇧Z to fit the whole show
  - J / K / L for reverse, pause and play; pressing L twice doubles the speed
  - hovering over a block for 1 second shows its info
- **Order list** on the right: thumbnail plus filename, drag to reorder,
  and it's the same order as the storyline
- **Both modes:** multi-select editing shows "mixed" values; a **Pan and Zoom
  editor** where you drag the start and end frames on the image; **⌘Z / ⇧⌘Z**
  undo and redo for every show edit

### Phase 2a: Framing, rotation and match cuts (added 2026-09-21, before 2c) — BUILT 2026-09-21, except presets (Flush), deferred
The main reason for this phase is **match cuts**: lining slide B up against
slide A so that the transition joins them seamlessly.

- **Transform (always on, Final Cut's model; settled 2026-09-21).** Every
  slide has a still placement on top of its fit: offset, scale, rotation,
  and an anchor point. It's where a match-cut nudge or a rotated still lives,
  so placing an image never depends on a motion effect being on. Scale can
  go below 1× and the image can hang past the frame's edges. Wherever the
  image doesn't cover the frame, a **background colour** set on the slide
  shows through. Pan and Zoom and Rotation add motion on top of the Transform
- **Inspector layout (settled 2026-09-21):** **Transform** (position,
  zoom, rotation) sits at the top of the column. It's the image's starting
  state. Below it is everything time-based: the transition in, Pan and Zoom,
  and animated Rotation. Jason counts animated rotation in that camp. The
  on-image handles edit the Transform; they never switch a motion effect on
- **Onion skin** (built 2026-09-21, not for video slides yet). While you frame slide B, slide A's **last frame** is drawn
  semi-transparent over it (an opacity slider and a toggle). It's an editing
  aid only and never renders into the show. It shows A's end frame exactly as
  it plays, including Pan and Zoom and rotation
- **"Soft at this zoom" flag** (built 2026-09-21: an orange triangle in the
  order list and on the storyline block, a line in the inspector, and the
  exact figure in the block's hover info; flagged above 1.25× the file's
  pixels on the main screen, at the slide's closest moment). When the framing shows the image with fewer
  pixels than the output, the slide gets a warning. This is where the
  upscaling hook later attaches (see the plugin seam)
- **Effects stack per slide (mix and match).** Each slide *use* can have
  several motion effects on at once, each with its own on/off checkbox in
  the inspector. Pan and Zoom (pan and zoom) and rotation are separate effects
  that combine. 2a's effects: **Pan and Zoom** and **Rotation**. The stack is
  also where later effects plug in
- **Rotation**, which works with Pan and Zoom or on its own. It has its **own
  interface** (its own inspector section and its own on-image editor: built
  2026-09-21 as the preview's Rotation mode, with green start and red end
  outlines, an arm per end to turn it, and pivot crosshairs), and
  it isn't folded into the Pan and Zoom editor (settled 2026-09-21). It has two modes,
  chosen per slide:
  - **Speed:** a speed slider (°/s). Note that trimming the slide then
    changes where the rotation ends, which moves a match-cut end frame
  - **Angles:** a start angle and an end angle, so the end frame stays put
    when the slide is trimmed. This is the mode for match cuts
  - **Acceleration** is a slider with **0 in the centre**: left decelerates,
    right accelerates. In Angles mode it shapes the way from start to end
    rather than changing the end angle
- **Pan and Zoom gets the same acceleration slider** (settled 2026-09-21),
  alongside its current easing, so a Flush can speed up its zoom as well as
  its spin
- **Pivot ("polar deviation").** The rotation point can be offset from the
  image centre. Two small polar grids (a joystick for start and one for
  end), with a **Lock** checkbox that keeps them the same. The pivot is
  pinned to the image, so it moves along with a Pan and Zoom pan
- **Transform handles on the image (Adobe conventions,** checked against
  Adobe's Photoshop help 2026-09-21). They act on whichever frame, start
  or end, is selected. The Pan and Zoom editor gets the scale handles; the
  rotate handle and the pivot crosshair live in the Rotation interface:
  - drag a **corner handle** to scale. Scaling is always proportional (it's a
    photo), and it's anchored on the opposite corner
  - **Option**-drag scales around the centre instead
  - move the pointer **just outside a corner**, where the cursor becomes a
    curved two-headed arrow, and drag to **rotate** around the pivot.
    **Shift** snaps to 15° steps (macOS has no built-in rotate cursor, so we
    draw one)
  - the **pivot** shows as a crosshair on the image (Photoshop's reference
    point) and can be dragged anywhere, even off the image. It's the same
    value as the polar grids, just shown in two places
  - a freshly placed slide image gets the handles straight away, so rotating
    it is one drag
  - no Enter/Esc commit step as in Photoshop: edits are live, and ⌘Z undoes
- **Selecting the image and the keyboard (settled 2026-09-21).** Click the
  image in the Edit Show preview to select it (outline and handles). Esc or a
  click on the background deselects. While it's selected, keys edit that
  slide's Transform:
  - arrows nudge 1 px, Shift+arrow 10 px (Photoshop and Keynote convention).
    A pixel means one pixel of the full-screen frame on the main display,
    not of the smaller preview
  - Option+←/→ rotate 1° anticlockwise/clockwise, Shift+Option 15°
  - Option+↑/↓ zoom in/out 1%, Shift+Option 10%
  - Option was chosen because ⌘+/⌘− already zoom the storyline and ⌘+arrows
    mean start/end across macOS
  - a run of presses is one undo step; the run ends after about a second
    without a key
- **Freeze on transition**: a checkbox on every effect that moves the
  image (Pan and Zoom, Rotation), **off by default**. When it's on, the effect
  holds its start frame through the transition in and its end frame through
  the transition out, and only moves while the slide is on screen alone.
  That makes a match cut through a dissolve exact. (Built in the model
  2026-09-21.) How to choose the frame a match cut lines up on is to be
  revisited only if eyeballing it proves hard in use
- **Presets** (deferred 2026-09-21: "we'll do something like that later")
  set several effects at once. They're a starting point, not a
  separate effect type. **Flush** is the first one: accelerating rotation
  plus zoom and pan, "down the hole"
- **Zoomable work area** (built 2026-09-21: a zoom menu and pinch on the
  Edit Show preview; the image is dimmed where it hangs past the frame).
  The framing editor and the preview can zoom out
  past the frame (a pasteboard around it), so an image that is rotated,
  shrunk or pushed off-centre can be seen hanging past the frame's edges,
  corners included. The frame edge stays marked
- **Corners:** a rotated image exposes the background at the corners. This is
  deliberately left alone until it has been seen (the zoomed-out work area
  is how to see it); the second layer (2c) may turn out to be the answer

### Phase 2c: The lane — transitions and image layers (after 2a) — BUILT 2026-09-21
Redesigned with Jason 2026-09-21 (this replaces the earlier "connected clip
on a slide" design). Above the storyline runs a **lane** with two rows:

- **Transitions row**, directly above the slides. Each transition is a
  **section sitting across the join** between two slides. The section *is*
  the overlap: its left edge is where the next image starts to appear, its
  right edge where the old one is fully gone (for a dissolve, the start and
  end of the opacity change). Its two edges move independently, but a
  section always touches or covers its join: it can end at the join, start
  at it, or straddle it (starting after the join would leave the outgoing
  image hanging on into the next slide's block). Drag the edges to set the
  window, or its middle to slide it; click the section and its settings
  (style, direction, duration) appear in the controls above the picture.
- **Default transition (Jason, 2026-09-21):** each show has one, and every
  join without its own transition uses it automatically. A new show's is a
  **2 s dissolve centred on the join**. It moves with its seam when slides
  are trimmed or rolled. Editing a section gives that join its own
  transition; "Use show default" puts it back.
- **A cut is no transition**: the slide blocks simply butt together and the
  transitions row is empty at that join. The storyline itself shows only
  the slides, butted together, with no transition markers on the cuts.
- **Images row**, above the transitions: image overlays (picture-in-picture,
  overlaps, PNG/HEIC with transparency) as sections placed freely in time,
  able to span joins, with gaps between them. One row, so two images never
  overlap each other. Selected, an image gets the handles on the main image
  and its settings (opacity, blend mode, fit, Transform, fades) in the
  controls above the picture and the inspector. Composited over the finished
  storyline picture.
- Still two picture layers in all: the storyline and one image row.

Timing model: each transition gets a **lead**, the seconds before the join
at which it begins (0 is how every transition worked before 2c, so existing
shows play unchanged). The show's length is still the sum of the slides'
lengths (join to join).

- **Adding images (Jason, 2026-09-21):** the images row is collapsed to a
  thin strip while empty and **expands when an image is dragged over or
  dropped into it** (from Finder or Photos). Or **right-click** in the lane
  at the mouse position: "Place Image Here…" picks one from the library.

**Parked, ask later:** whether an image section stays at its time on the
clock or moves with the slide it starts over when slides are trimmed or
reordered ("stickiness"). Jason wants to decide once he has set up his own
files as a test bed: **ask him then.** Until then images stay at their time
on the clock.

### Inspector: the slide, then its effects (Jason, 2026-09-21)
The inspector is the slide itself (file, rating, placement: fit, position,
zoom, rotation, background; its length), then an **Effects** section: a
display-only timeline of the slide's time on screen with a bar for each
thing acting on the picture (transition in and out, Pan and Zoom, Rotation,
lane images over it; hatched where freeze on transition holds still), then
the effects' controls. Built 2026-09-21. The bars may become draggable
later; they aren't, because most timings come from other settings.

### Frame strip (built 2026-09-21)
A strip of rendered frames of the finished picture (slides, transitions,
lane images) **under the picture, in the main viewer's column only**, so the
browser and inspector keep their full height (Jason). One divider between
picture and strip sizes it: bigger frames each cover more time, so fewer
show. It can **follow the storyline** (frames over their moments, scrolling
with the blocks; the default) or show the **whole show** across its width,
from a small menu on the strip. Click a frame to go there. **View ▸ Show
Frame Strip (⌥⌘F)**. Frames render in the background through the
Compositor from small copies of the files, cached by time. Video shows its
first frame for now.

### Plugin seam (internal, our own plugins only)
Tools that make or alter media sit behind one interface: library media in,
new library media (or a render step) out. The first candidates are
**AI upscaling** (an upscaled copy stored next to the original, which the
slide then uses), the **collage maker** (a new library image; to be fleshed
out before it's committed to) and **stamps**. It is internal only:
App Store rules forbid downloading or running code that adds features after
review, so any add-ons would ship inside the app. The upscaling engine is
chosen later, after checking what macOS actually offers.

### Phase 2b: Library manager — BUILT 2026-09-21
**Starts with Collections (Jason, 2026-09-21).** The app is organised the
way Final Cut is (Library → Event → Project), with ShowTools' own names:

- **Library → Collection → Show** in the sidebar. A **Collection** is a
  defined set of the library's photos (a photo can be in several); a
  **Show** belongs to a collection and is built from its photos.
- **One master library**, as now, so duplicates are caught across it and
  "random from all files" means everything. There's also the ability to
  **load an alternate library** when needed (as Final Cut and Aperture
  can). Any library location obeys the same rules (hidden from Spotlight by
  default, never in iCloud).
- The right-hand list becomes the **Collection Browser**: the collection's
  files, dragged from there into the storyline or the images row. The
  show's order lives in the storyline (which already reorders by drag). The
  browser has **a bar at the top with an arrow showing there's more to
  expand**.
- **A file that isn't in the show's collection** (dropped from Finder or
  Photos, or from elsewhere in the library) brings up a dialog: "…isn't in
  the collection. Add it?" with Add to Collection / Cancel and the standard
  suppression checkbox, labelled **"Always add without asking"** (it only
  means anything with Add, so Cancel can't become a silent refusal).
  Ticking it switches on a preference, **"Add files to the collection
  automatically"**, which is also where it's switched back off.
- Existing shows (only the test show so far) go into one starting
  collection.
- **Importing (Jason, 2026-09-21):** File ▸ **Import…** (⇧⌘I) puts files
  into a collection: its panel has an "Import into:" menu (every
  collection, New Collection, Library Only), starting on the collection
  you're in. File ▸ **Add to Library…** (⌥⇧⌘I) imports into the library
  only. File ▸ New Collection (⌥⌘N). Many files and whole folders at once.
- **The Library view is a photo grid like Photos or Aperture:** a size
  slider, a bar at the top with search, filters (kind, minimum stars, "Not
  in Any Collection") and sort (date added, name, rating), Finder-style
  multi-select, and selected files drag onto a collection or a show in the
  sidebar. A collection's view is the same grid.

The rest of 2b below (browsing, delete, rename, Info, relink) then applies
to the Collection Browser and the library.

- **The browser's bar:** its arrow opens the **inspector column**; the bar
  also holds the **search field and filtering tools** for the list.
- **Libraries switch, one at a time** (as Photos does): File ▸ Open
  Library…, New Library…, and **Open Recent**. The app always starts on the
  master library; if the master is private it opens on a locked screen
  with Unlock (built 2026-09-21), rather than asking before there's a
  window.
- **Private libraries:** a library can be marked private. A private library
  is **left out of Open Recent**, is **never reopened automatically**, and
  opening it asks for **Touch ID or the Mac's login password**
  (LocalAuthentication's device-owner check). The mark lives in the library
  itself, so it holds wherever the library is opened from. Turning it off
  asks too. ShowTools must leave no copies or previews of a private
  library's photos outside its folder (thumbnail caches included).
  **Limit, told to Jason:** this guards the door in ShowTools only; the
  files are still ordinary files to anyone using the Mac account. Real
  locking means keeping that library in an encrypted disk image, with
  ShowTools as a second lock.
- Browse the whole library: thumbnail grid, sort and filter (type, date, size,
  "not in any show")
- **Delete** follows the Photos convention:
  - **Delete** asks first. The prompt names how many shows use the item(s)
  - **⌘Delete** moves the file(s) straight to the Trash, with no prompt
  - Either way the file goes to the macOS Trash (so it can be recovered), the
    library entry is removed, and every slide using it is removed from its
    shows. **⌘Z** undoes it while the file is still in the Trash
- **Batch rename** of library files, modelled on Finder's *Rename Items*
  sheet (select several, then File ▸ Rename): the same three modes, **Replace
  Text**, **Add Text** (before or after the name) and **Format** (a name plus
  an index, counter or date, with a start number), with a live preview of the
  new names before anything changes. Only the copies in the library are
  renamed, and the database follows, so shows are unaffected
- **Info panel** (a floating side panel, like ⌘I in Photos) for the selected item(s):
  - file metadata read from the image: dimensions, file size, format, date
    taken, camera and lens, exposure and GPS where present (read only)
  - **tags** you add yourself. Several items can be tagged at once. Tags
    feed the library search and filters
  - tags are always stored in the database. A setting, **"Also write tags as
    Finder tags"** (off by default), additionally puts them on the library
    files as macOS Finder tags
- **Relink** files that have moved or gone missing, re-found by their hash

### Phase 3: Music + timeline — BUILT 2026-09-22 (all 7 steps)
(Decisions from Jason, 2026-09-21, unless marked otherwise.)
- **Modular rows.** Every timeline row (transitions, images, slides, music)
  is a module, and the rows can be dragged into any order. Each row has a
  small **header** at its left end (like Logic's track headers, which Final
  Cut doesn't have). Reordering is built in this phase, not later.
  - **The order belongs to the show** and is saved with it, so it reflects
    how that show is built. Rearranging is a show edit, undoable with ⌘Z.
    New shows start in the default order: images, transitions, slides,
    music. It's stored as a list of rows, not a fixed set, so a show can
    have more rows later (a second images row, say).
  - **Headers are drawers.** A thin strip with a grab handle (≡) is always
    visible. Drag it to reorder the row; click it and the drawer slides
    out **over** the row's content (the timeline doesn't move), showing the
    row's icon, name and controls. Click again or press Esc to close it.
    A click opens that row's drawer; **⌥-click** opens or closes them all.
  - **The ruler stays pinned on top.** It's not a movable row. The playhead
    and the In/Out points live there.
  - An **empty row keeps its full height**, with a faded placeholder in it
    (the images row used to shrink to a thin strip).
- **The music row** sits at the bottom by default. Songs are **copied into
  the library**, like photos, so relink, delete and export already cover them.
- **Audio clips work like image clips.** Add as many as you want, drag one
  to move it, and drag its edges to trim it (trimming the front edge cuts
  into the start of the song, as in Final Cut). Songs share **one row**.
  Where two overlap they crossfade; one song draws light blue and the
  overlap draws light green (or something similar) so it's easy to see.
- **A level line on each clip.** Each clip gets a simple ramp you adjust on
  the clip itself: a level you drag up or down, with fade handles at each
  end. It's volume on an audio clip. **Image clips get the same control for
  opacity.** They already store opacity and fades (set in the Inspector),
  but there are no handles on the timeline yet.
- **The show is as long as its longest row**, not just its slides. Drop an
  image or a song that runs past the end, and the show gets that much
  longer. Time after the last slide shows the **show's background
  colour**. Slides already have their own background colour (in the
  Inspector); the show-wide default, fixed at black until now, gets a
  control in the Edit Slides header bar. With loop on, the whole show
  restarts after its longest row ends. When something runs past the
  slides, the loop's restart is a cut from the background into the first
  slide (there's no last slide to transition from), and the last slide
  cuts to the background (built 2026-09-21; a fade could come later).
- **The waveform** is decoded once and cached.
- **Scrubbing scrubs the show.** It's silent by default. A button in the
  music row's header turns scrub audio on.
- **Markers, two kinds:**
  - **Manual:** press M on the beat. These stay at their time on the show's
    clock and move only when selected and dragged together.
  - **Detected:** generated from a song, so they belong to that audio clip
    and move with it. Automatic detection is **in this phase** (it was
    deferred until 2026-09-21). How detection is set up and applied (a
    range, beats per slide, a rhythm pattern) is below.
- **Snapping:** slide cuts and image clip edges snap to markers. N turns
  snapping on and off.
- **Video sound:** muted by default. Punted until Jason makes a first show
  (2026-09-21). The idea is a volume line along a video slide's own length,
  so you keep the part where someone speaks and drop the part with the dogs
  barking.
- **Image stickiness** (parked in 2c): settle it at the end of this phase,
  once Jason has made a first real show.

#### Beat detection, the range, and rhythm (settled 2026-09-21)
- **The detector is Apple's Music Understanding framework** (Jason,
  2026-09-21): on-device beats, bar starts, tempo, and the song's
  sections, segments and phrases. It needs macOS 27, so step 6 waits
  until Jason's Mac is on it. Our own detector was considered and turned
  down. Still to settle when step 6 starts: analysing each song
  automatically on import (cached like the waveform); beat and bar ticks
  and section bands on song clips (double-click a section to set the
  range); where the apply sheet opens, and its preview; detected markers
  in teal, belonging to their song; ×2 / ÷2 and "bar starts here" in
  place of tap tempo.
- **The range:** I and O set in and out points, drawn as two blue markers
  on the ruler with the span between them shaded (Final Cut's convention).
  A toggle extends them as lines down through every row; off, they're
  just the triangles on the ruler.
- **Lines, two kinds (Jason, 2026-09-21):** the markers' lines and the
  range's lines each have their own switch in the transport bar.
  Double-click one marker (or one end of the range) for just its line;
  ⌥-double-click for every one of that kind.
- **The show's editing state is saved with it** (Jason, 2026-09-21), so a
  show opens the way it was left, like its row order: the range and
  whether it's on, loop playback, and the lines. It isn't undoable (undo
  keeps it as it is), but marker edits, a marker's own line included, are.
  It's multi-purpose by context: the part detection applies to, and, with
  loop on (⌘L), the region playback loops inside while editing. Option-X
  clears it, and a header button turns it off without losing it.
- **Tempo:** the song's tempo (BPM) and beat grid are detected, with a
  field to override them and a tap-tempo button for when it guesses half
  or double. Slide changes quantize onto the *detected* beats, not a perfect
  grid, so a song that drifts is still followed.
- **The apply sheet**, run on the range: roughly how many beats per slide,
  *or* a change every roughly X seconds, *or* a rhythm pattern (below).
  It always drops markers (detected ones, so they belong to the song). A
  **"Fit slides to markers"** switch also resizes the slides, from the one
  the range starts in, so each ends on the next marker. Slides are never
  split: they're resized, and the ones after follow (Jason, 2026-09-22).
- **Rhythm patterns** (step 7, planned with Jason 2026-09-22). A note's
  value only sets the gap from one slide change to the next. "Staccato" was
  colour, not a literal feature. It did spark an idea for a **strobe
  effect**, which is parked under Later.
  - **Two tools.** The **Rhythm** tool writes a pattern and works on its
    own, with no song and no analysis: it lays the pattern on an even BPM
    grid and drops **orange hand markers** (a re-run adds more; ⌘Z to try
    another). **Detect Beats** gets a fourth marker choice, **Pattern**,
    which opens the Rhythm tool for its pattern and lays it on the song's
    detected beats as teal markers, with the preview, marker count, Fit
    slides and one-step undo it already has.
  - **Writing it: one text field is the input.** Type into it, or click the
    glyph legend (each note glyph with its letter, a "Rosetta stone") to add
    that letter. The pattern is drawn as **notation** and as a **step grid**
    (tabs), both following the text.
  - **The letters:** `w h q e s` (whole, half, quarter, eighth, sixteenth);
    a dot after a note adds half its length (`q.`); `3e` is one note of an
    eighth-note triplet, so `3e 3e 3e` lasts a quarter. **`r` before a
    value is a rest** (`rq`, `rh.`): it takes time but drops no marker, so
    `q rq q` changes on beats 1 and 3. No ties (a note's value is only the
    gap, so `h`+`q` tied is `h.`). An empty grid square is a rest.
  - **Notation:** one rhythm line, no pitches, drawn with Bravura (the
    free SMuFL music font, SIL OFL 1.1: licence checked 2026-09-22 and
    bundled with it in `Resources/Fonts/`; the legend uses it too). Eighths
    and sixteenths beamed within the beat, triplet brackets, bar lines.
  - **The grid** is its own input, like a drum machine: click a square to
    put a change there. In grid mode the text field and the letter legend
    are hidden (Jason, 2026-09-22). It sizes itself: 16 or 12 steps a bar
    (12 for triplets), as many bars as the pattern needs. A pattern it
    can't show leaves it read-only with a note saying why.
    Clicking rewrites the letters: each gap is one note, never running
    past its bar line, then rests, also split at bar lines, so a
    quarter before an empty bar reads `q rw` (Jason, 2026-09-22).
  - **Note length:** "A quarter note = [¼, ½, 1, 2, 4, 8] beats", default
    4 beats (one bar), so `q q q q` is a slide a bar.
  - **Tempo:** a **BPM field**, filled in from the song's analysis when
    there is one, otherwise 120; always editable (see below).
  - **Where it starts:** the start of the range, or of the show with no
    range. It repeats to the end, and the last repeat is cut short. On a
    song it counts the detected beats (between beats, in proportion), so a
    drifting song is still followed; ×2 / ÷2 and "bar starts" apply.
  - **Saved patterns:** the last one used is remembered; a few built-ins
    (steady `q`; long-short `h q q`; build `w h h q q q q e e e e e e e e`;
    a triplet feel); and Jason's own named patterns, saved in the library
    and offered in a menu, each with its note length (Jason, 2026-09-22).
  - **Listen:** loops the range with a click on each pattern note (over
    the song when there is one), before applying.
  - **The Rhythm tool is a floating panel** that stays open while you
    work, applied to the range as often as you like, with its own **Fit
    slides** switch. It opens from the slides row's drawer and the Show
    menu (with a shortcut). From Detect Beats, Pattern shows the pattern's
    text with **Edit…**, which opens the panel; the pattern comes back
    when it closes.
  - **Typing a BPM over a song** drops the detected beats for an even
    grid at that tempo; **"Use the song's beats"** goes back. (The BPM is
    filled in from the song's analysis.)
  - **No "every N beats" without a song:** a steady `q` pattern does it.

### Phase 3b: Find Similar, and Delete by context (planned with Jason 2026-09-22) — BUILT 2026-09-22
Rethought from "duplicate finder": exact duplicates can't exist in a library
(the hash is unique and import skips a file it already has, saying "already
in library"), so the value is in **grouping similar pictures**, for building
shows, and in **keeping one of a series** that got imported.
- **Delete by context first** (Apple's Photos convention, checked in its
  keyboard-shortcuts table: Delete removes from an album but not the
  library; ⌘Delete deletes from the library):

  | Where | Delete | ⌘Delete |
  |---|---|---|
  | Library | Trash, asks first | Trash, no question |
  | A collection | Remove from the collection (undoable) | Delete from the library: Trash, **asks first** |
  | A show's slides | Remove the slides | Same |
  | Edit Show's collection column | Remove from the collection | Delete from the library, asks |

  **Undo for collection deletions** (Jason): Remove from Collection, and
  deleting a whole collection (its shows come back with it).
- **Group Similar:** a switch in the Library/collection toolbar with a
  **similarity slider**; the grid shows similar pictures together in
  groups, regrouping live. The grid's usual actions work on them.
- **Show Similar** on one picture's right-click menu: the grid narrows to
  pictures like it, with the same slider.
- **Scope:** what you're viewing (the library or one collection). Still
  pictures only. **Fingerprints** (Vision's image feature print; the
  older `VNGenerateImageFeaturePrintRequest` works on macOS 14) worked out
  once per picture in the background, with progress, cached by hash.
  No "not similar" marking: the slider is enough.
- **Keep One…** on a group: side by side, a suggested keeper (largest, then
  highest rated), click to change. The others go the way Delete goes where
  you are (out of the collection, or to the Trash in the library), as one
  undo step. **A file a show uses is left alone**, and it says so ("2 kept:
  used in shows"). Files sent to the Trash give the keeper their tags and
  the highest rating.

### Phase 4: Setlist export / import (replanned with Jason 2026-09-22) — BUILT 2026-09-22 (risks: see handoff)

The first version of this section (2026-09-20) was written before slides had
transform, rotation, background or clip start, and before shows had the
images row, songs, markers, rows or editing state. Its flat TSV could no
longer carry a show, so it was replanned against what exists now.

**What it's for (Jason, 2026-09-22): both.** A folder of numbered copies to
use outside ShowTools (a USB stick, a TV, another app, Finder), *and* a way
to move a show to another library or Mac and get it back exactly. So import
must be lossless.

**The folder:**
```
Beach Trip/
  show.json          everything, exactly
  show.tsv           the readable one: open it in Numbers, edit, re-import
  001_beach.jpg      the slides, numbered in show order
  002_sunset.jpg
  ...
  music/             the show's songs
  overlays/          the images row's files
```
- **Slides at the top level, numbered** in show order. The number is padded
  to the slide count (a 1,200-slide show gets `0001_`), so Finder's order
  is the show's order. Songs and images-row files go in `music/` and
  `overlays/`, so they never interleave with the slides
- **The name after the number is the file's current name in the library**
  (after any batch rename), not the name it arrived with
- **One numbered file per slide**, even when the same photo is used several
  times. Unstripped copies are APFS clones, so on the same drive they cost no space; on
  another drive they're ordinary copies
- **Copies have their metadata stripped by default** (see "Settled" below).
  The originals in the library are never renamed, moved or changed

**`show.json`: the whole show.** The defaults, every slide's settings
(length, transition, Pan and Zoom, fit, clip start, transform, background,
rotation), the images row, the songs (start, in point, length, volume,
fades, their markers), the show's markers, its row order and its editing
state. Slides, songs and overlays refer to files by their path in the
folder, and carry the file's library hash so import can match what's already in the
library. It also carries each file's tags and rating, which import applies
only to files it brings in new. Caches (thumbnails, waveforms, similarity
prints) are not exported; they're rebuilt. A `"version": 1` field lets
later formats read old exports.

**`show.tsv`: the readable one, still editable.** Tab-separated, one line
per slide, a header row, show-wide defaults in `#` lines at the top, an
empty cell means "use the default". As built in 4a:
```
# ShowTools setlist v1
# name	Beach Trip
# default_length	5
# default_transition	dissolve 2 lead 1
# default_panzoom	off
# default_fit	fit
# default_background	#000000
# video_clip_length	yes
# loop	yes
# music	music/song.m4a
file	length	transition	panzoom_start	panzoom_end	fit	rotation	background
001_beach.jpg	8		0.5,0.5,1	0.3,0.4,1.4
002_sunset.png		swipe left 0.5
003_beach.jpg						0 to 90
```
Text forms: a length is seconds or `clip`; a transition is its style, its
direction when the style has one, the duration, and `lead N` when the lead
isn't 0; Pan and Zoom is `off`, `auto`, or `x,y,zoom` start and end; rotation
is `off`, `0 to 90` (angles) or `30/s` / `30/s from 10` (speed); a
background is `#rrggbb`. Numbers are written with at most three decimals.
Transform, the images row, songs and markers are in the JSON only; the
`# music` lines name the songs so the file makes sense on its own.

**Import: the JSON supplies everything, the TSV has the last word on what
it shows.**
- Slide order comes from the TSV's rows. Its columns override the JSON for
  that slide, so edits made in Numbers win
- A row deleted from the TSV drops that slide. A file added to the folder
  and given a row becomes a new slide with default settings. Rows are
  matched to the JSON's slides by filename (unique, since they're numbered)
- **A cell still reading what export wrote keeps the JSON's exact value.**
  The TSV rounds (three decimals, `#rrggbb`) and summarises (a rotation's
  pivots, a Pan and Zoom move's easing aren't in it), so only a cell that
  differs from what export would write for the JSON's value replaces it.
  A changed Pan and Zoom or rotation cell keeps the JSON's other details
- A row copied in the spreadsheet is a second use of that slide: same
  settings, its own auto Pan and Zoom move (as Duplicate gives in the app)
- A cell that can't be read keeps the JSON's value and is listed in the
  import's problems, with its line number
- **Auto Pan and Zoom stays the same move.** It's seeded from the slide's id,
  which a new library won't reuse, so `show.json` records each slide's
  original id and import carries it over as the slide's seed (an additive
  field in the slide settings, 4b)
- No TSV: the JSON alone. No JSON: the TSV alone, with everything it
  doesn't carry left at its defaults. Neither: see below

**Where an import goes:** a new show named after the folder, in the open
library and the current collection. Files already in the library (same
hash) are reused, not imported twice.
- **"Make a collection for it"** (Jason, 2026-09-22): a checkbox in the
  import panel that puts the show and its files into a new collection named
  after the folder instead

**A folder with no manifest at all:** a new show from its files in Finder's
name order, every slide on the defaults. In effect, "New Show from Folder".
Songs in such a folder aren't placed; the import lists them to add by hand
(built this way in 4b; say if they should go in the music row instead).

- **The same checkbox on File ▸ Import…** (Jason, 2026-09-22): when a
  folder is imported, "Make a collection for it" puts its files into a new
  collection named after the folder. As built (4d) it reads "Make a
  collection for each folder", since Import… takes several: each chosen
  folder gets its own collection (`.noindex` dropped from the name), and
  files chosen on their own still go where "Import into" says
- A name already taken gets a number, as New Show and New Collection do

**Settled with Jason 2026-09-22 (questions 7 to 11, as suggested, plus 9):**
- Scope: the whole show only. Exporting the range or a selection can come
  later
- **Privacy: metadata is stripped on export by default** (Jason). GPS,
  camera, dates and the rest come off the copies. A Preferences setting,
  "Strip metadata from exported files", turns it off; with it off, copies
  are byte-exact APFS clones. Measured 2026-09-22 (4a): JPEG is
  copied losslessly with its metadata replaced; HEIC, PNG, TIFF and
  animations are written afresh from their frames (pixel-identical in the
  tests; HEIC is lossy in principle, at quality 1.0); video and songs are
  remuxed, samples untouched (a real song decoded sample-for-sample the
  same). Orientation, animation timing and an AAC song's gapless figures
  are kept. **Songs keep their tags** (Jason, 2026-09-22): title, artist,
  album and the rest stay; only a purchased song's Apple ID, owner,
  purchase date, store and account type, and any location or recording
  date, come off. (`.forSharing()` was tried and dropped title and artist
  too.) Jason's two test songs kept all 17 tags, sample-exact. Every copy is read back: anything else left in it and the file
  is copied unstripped instead, listed in the export's result for the panel
  to show. A stripped copy has a new hash, so `show.json` records
  each file's *library* hash as well: import matches on that first, so a
  round trip into the same library reuses its files instead of importing
  near-copies
- The library is hidden from Spotlight; an export folder isn't. A "Hide
  from Spotlight" checkbox in the export panel adds `.noindex` to the
  folder's name, on by default when the library is private
- Exporting over an earlier export of the same show replaces it (the old
  folder goes to the Trash). Any other folder that isn't empty is refused
- Menu names: File ▸ Export Show… (⇧⌘E) and Import Show…. File already has
  "Import…" (files into the collection) and "Add to Library…", so the names
  must not blur with those. Checked 2026-09-22: Apple's guidelines define
  only "Export As…", for document apps writing a format they don't usually
  handle (the exported file isn't opened). Photos, the nearest app to this
  one, names the object: "Export Photos…", ⇧⌘E. So "Export Show…", ⇧⌘E
- Whether Numbers can save the TSV back as TSV (it may only export CSV):
  "we'll find out" (Jason, 2026-09-22), in 4e

**Build steps:** 4a core export, 4b core import, 4c Export Show… panel,
4d Import Show… panel (and the collection checkbox on Import…), 4e a
hands-on round trip on a scratch library, including an edit in Numbers.

### Phase 5: BGTools, the desktop companion app (renamed 2026-09-22; was "Live desktop") — BUILT 2026-09-22
**Its own spec: `spec/bgtools.md`** (decisions, measurements, open
questions). In short: a small separate app that ShowTools installs, which
plays shows as the desktop picture on each monitor and Space, reading the
library read-only; Control Center opens it, its menu bar icon is
optional. **Built 2026-09-22 (B1–B7)**: the shared player
(`ShowToolsPlayback`), the read-only library reader, desktop windows per
monitor and Space, five play modes with per-screen settings, BGTools'
window and panel, its two Control Center tiles, pausing (sleep, lock, Low
Power, hidden Spaces) and private libraries behind Touch ID, and
installation from ShowTools. See `spec/bgtools.md` for what's left.

### Design posture: the six essentials (Jason, 2026-09-24)

A slideshow is six things: **the pictures, their order, how long each
shows, how one gives way to the next, whether they move, and what plays
under them.** Jason designed the app around them before they were
counted, and they turn up in Quick Show, New Show and BGTools alike.
**Perceptual efficiency:** wherever someone starts, the six come first and
nothing gets ahead of them; everything else refines one of them and waits
until asked for. New panels and levels are checked against the six.
Detail: `spec/simple-things-fast.md`.

### Pan and Zoom, and simple things fast (Jason, 2026-09-22; renamed 2026-09-24)

**"Ken Burns" was renamed "Pan and Zoom"** everywhere it was shown. The old
name was a reference, not a description; the new one says what the
control does. **Done 2026-09-23**, in one pass: the UI, the code
(`PanAndZoom*` types and properties), the slide-settings JSON keys
(`panAndZoom`, `panAndZoomSeed`) and the setlist TSV columns (`panzoom_*`,
`default_panzoom`). Every show in the library was disposable test
material, so no old spelling was kept decodable — confirmed by hand
against a real setlist folder exported just before the rename: its old
`kenBurns`/`kenburns_*` spellings come back unread and silent (no
`problems` entry). See `spec/status.md`.

**It is an effect, and effects are not a slide's default state.** Phase 2a
separated a slide's starting placement into the Transform section, which
leaves Pan and Zoom as something applied *on top*. So it should not be on
by default for a new slide. It belongs instead to a choice made when a
show is started — "make me a slideshow that gently moves" — rather than a
setting every slide quietly carries. **The show-level default was already
`.off`** (`ShowDefaults.panAndZoom`). BGTools'
`DesktopSettings.startingRandomDefaults` was the one default still set to
`.auto` — flipped to `.off` the same day, since it's also the one that
measurably costs CPU (see Known Issues in `spec/status.md`).

**The larger point, not yet designed:** this editor is deliberately
detailed, and that makes a plain slideshow harder than it should be.
There should be a simple way in (now **simple things fast**, its own
spec: `spec/simple-things-fast.md`) — a way for the app to look easy for
someone who just wants pictures in order with music, while everything
underneath stays where it is. Related to the guided first run below, but
not the same thing: that teaches the app as it is, this changes what you
meet first. **To be designed with Jason.**

### Groups inside collections (Jason, 2026-09-24) — Planned, to build right away

A collection gets **groups**: sub-folders of its files, so a big
collection can be organised without splitting it into several
collections. Being designed now, then built by the Mac session.

*What exists today (from the code):*
- Collections are flat: `collections` (id, name, created_at) and
  `collection_items` (collection, item, added_at). A file can be in
  several collections.
- Every show belongs to one collection (`shows.collection_id`) and draws
  its pictures from it.
- The library is at **schema version 12**. Groups need new tables, so
  they're **migration 13**: additive, `Library.schemaVersion` raised to
  13, and tested by opening a version-12 library (CLAUDE.md).
- **A name clash:** the grid's **Group Similar** already calls its
  look-alike sets "groups". One of the two needs another name.

**Decided (Jason, 2026-09-24):**
- **What a group is: a book cart.** Something you load up for now, more
  temporary than a collection. Deleting a group leaves its files in the
  collection, and in every show that uses them.
- **Membership:** a group's files must be in its collection. A file can
  be in several groups.
- **Nesting:** groups hold groups, like folders.
- **In the Library pane:** a collection opens to show its **groups and its
  shows side by side**, as siblings. Shows don't live inside groups, and
  aren't limited by them. Files can be dragged onto a group there.
- **Order:** creation order by default, with a choice of alphabetical and
  others (size, length).
- **Using a group:**
  - **A show can draw from a group:** the browser (the collection's files,
    in Edit Show) gets a **drop-down in its title** to filter by group.
  - **A Quick Show's pool** can be a group.
- **The name clash:** Group Similar becomes **Find Similar Images**
  (Jason's leaning), so "group" means only this.
- **Keep as Group:** a set found by Find Similar Images can be kept as a
  group from its header. Jason's example: the similar pictures are all so
  good he can't choose yet, so they go in a group for later. Once he's
  decided, he keeps one and deletes the group.

**A proposal for the build** (Claude; the Mac session confirms it against
the code):
- **Migration 13:**
  - `groups` (id, collection_id → collections ON DELETE CASCADE,
    parent_id → groups ON DELETE CASCADE, null at the top; name,
    created_at);
  - `group_items` (group_id → groups ON DELETE CASCADE, item_id → items
    ON DELETE CASCADE, added_at; primary key group and item).
  - `Library.schemaVersion` to 13, and a test that opens a version-12
    library.
- **Keeping the membership rule:** taking a file out of a collection also
  takes it out of that collection's groups, in the same transaction.
- **Shows and groups need no schema.** A show still belongs to its
  collection, and the browser's group filter is view state, remembered
  with the show's editing state.
- **Undo** for creating, renaming, deleting and filling groups, like
  collections.
- **Order:** the sort choice is a view setting, not stored per group.

- **Deleting a group that holds groups** (Jason): its sub-groups go with
  it, as in Finder. The confirmation says how many groups will be
  deleted ("This also deletes 3 groups inside it. The files stay in the
  collection."), and has a **Do not show this message again** checkbox,
  as the slide-removal notice does. Files are never deleted with a group.
- **Keep as Group with no collection open** (the Library view; Jason): a
  dialog explains that a group lives in a collection, so saving this one
  needs a collection first. It offers to create one, with **Grouped
  Collection** suggested as its name. After that, the usual naming step
  for the group follows. (In a collection, the group simply goes in the
  collection being viewed.)

### Later
- ~~Video export~~ — **BUILT 2026-09-22**, E1–E5, through the hook above
  exactly as promised: a new menu item, not a rewrite. Own spec
  `spec/video-export.md`
- ~~Beat detection~~ (moved into Phase 3, 2026-09-21)
- **Pan and Zoom that pans, with a direction, and a point to aim at**
  (Jason, 2026-09-24: "the pan and zoom currently only zooms").
  *From the code:*
  - **Auto** is mostly a zoom (`ShowTimeline.autoPanAndZoom`): from 1× to
    1.12–1.25×, with a drift of at most 8% of the image, in or out at
    random.
  - **Custom** can pan. The inspector's small editor has a green start
    frame and a red end frame to drag, which is easy to miss.
  - With **Fit** at 1× there's no room to pan at all; the image already
    fits the frame. A pan needs zoom, or Fill.

  *Wanted:*
  - a way to pan, with a **direction** (left, right, up, down, or a
    choice for Auto);
  - a way to put the **zoom-to point** on the image by clicking, or a
    modified click (⌥-click, say), in the viewer or the Slide Editor
    (`spec/windows.md`), rather than dragging a small frame in the
    inspector.
- **Audio rows stack** (decided, Jason, 2026-09-24): a show can have
  more than one audio row, for music under a voice, or sound effects over
  a song. Added from the timeline (Add Audio Row, on the audio row's
  right-click).
  *From the code:*
  - The rows model already expects it. `TimelineRow.normalized` keeps one
    row per kind "for now", noting that "that rule relaxes when a show
    can have more than one row of a kind".
  - An `AudioClip` doesn't say which row it's on, since there's been only
    one. Stacking adds a row reference to each clip. It's a new field in
    the show's JSON, decoded on its own (CLAUDE.md), where no reference
    means the first audio row, so every saved show still reads. No
    library migration.
  - Within a row, overlapping clips crossfade, as now. Across rows, they
    mix.
  - **What it's for (Jason):** mostly crossfading music, and laying sound
    clips on top of background music. Not stacking several songs.
  - **The mix already sums** (checked 2026-09-24). Live, `MusicPlayer`
    gives every clip its own player node, all feeding one mixer, so any
    number of clips play together. Export mixes offline
    (`MovieSoundTrack`) the same way. It's the audio engine that mixes;
    the database only stores where each clip sits.
  - *One thing to watch:* two clips at full level can add up past full
    scale and distort. A limiter on the final mix is the usual guard. A
    video slide's sound was decided to "just mix, no ducking"
    (`spec/video-audio.md`); ducking music under a voice could be an
    option later.
  - *Row controls:* each clip already has its level line. A row's own
    volume and mute may find their place in the rows' drawers once
    they're rearranged (`spec/windows.md`, the timeline pane's left edge).
    Not thought out yet (Jason).
  - *To settle:* how Detect Beats and the Rhythm tool choose a row, and
    whether several *images* rows follow the same way (the plan mentions
    "a second images row").
  - *Naming:* Jason said "audio track". The app's word is **row**
    (`spec/anatomy.md`), so the menu item says **Add Audio Row**.
- **Replace a slide's image** (Jason, 2026-09-24): a tool to change which
  picture a slide (or lane image) uses, keeping everything else about it.
  *From the code:* a slide is its id, its file (`itemID`) and its
  settings, and every position in the settings is a fraction of the
  image or frame, not pixels. So replacing is pointing the slide at
  another file: length, transition, Pan and Zoom, transform and effects
  carry over proportionally. A picture of a different shape frames a
  little differently. Only pictures replace pictures (`model.pictures`);
  one undo step; a file from outside the show's collection asks first,
  like any add. *Ways in (settled, Jason, 2026-09-24):*
  - **Replace Image…** on the right-click menus of a slide, a lane image
    and **the inspector**, opening a picker of the collection;
  - **dragging a file onto a slide**, in the timeline or in Edit Slides'
    list: the drop offers **Replace** or **Insert**, as Final Cut's replace
    edit does. (Today a drop always inserts, and in the list it
    appends, audit G2.)
- **A strobe effect** (Jason, 2026-09-21): a slide flashing on and off
  against the background colour. Came out of the rhythm-pattern talk
- Photos-library browsing inside the app. Deferred until the app has taken
  shape; the permission question gets worked out then. **Checked
  2026-09-24:** no paid developer membership is needed. ShowTools isn't
  sandboxed, so it needs a usage line in Info.plist and the user's
  permission. The catch is that an ad-hoc signature may make macOS ask
  again after each rebuild, which a free Apple ID's Personal Team signing
  would avoid (`spec/conventions.md` §5). Drag-and-drop from
  Photos works from Phase 1 regardless
- **A guided first run** (Jason, 2026-09-22), to be fleshed out with App
  Claude; brief in `spec/first-run-brief.md`. Not a separate tutorial:
  each *first encounter* teaches itself, one step leading to the next. A
  welcome when everything is empty (its button: add images); the first
  visit to the empty collection explains collections, with a Rename this
  collection button (default name maybe "My First Collection") that goes
  once it's renamed, leaving Import; the inspector's first opening shows a
  cover ("This is the inspector, it's for…", Got it) that closes the window
  if nothing is selected or uncovers the clicked file's info. After the
  first time, empty places say something plain, as they do now. Needs the
  rules of organisation and the lingo (library, collection, show, slide,
  song…) stated first, since they never have been
- **Windows of their own** (Jason, 2026-09-24): areas of the main
  window (sidebar, library, browser, inspector, timeline pane) that can move
  into windows of their own, and editors opened on one thing: a row, or a
  slide in the **Slide Editor**, which is where the collage maker below
  would live. A vision, not designed: `spec/windows.md`
- **A collage maker** (Jason, 2026-09-21b), parked here to think through
  rather than build straight away. Two ideas so far, which may turn out to
  be the same feature seen two ways:
  - A gradient mask to blend two photos on one slide: two points pinned to
    the slide frame's edges with a line between them, a handle at the
    line's centre that pulls out at right angles to set how far the
    gradient reaches, and a further handle on that pull-out to set the
    gradient's midpoint weight
  - Multi-panel slides (2 or 3 images arranged "1 2 3" across one slide)

---

## Settled 2026-09-20

- Desktop randomizing: a four-way play mode per monitor (none / random from
  show / random show / random from all files) plus an "All same" checkbox.
  Random show plays the picked show in order; random from show shuffles it.
  (2026-09-22: carried into `spec/bgtools.md` as open questions)
- "All files" means everything the app has ingested: the library database
- The library is managed: files are copied into `~/Pictures/ShowTools Library/`,
  which is kept out of iCloud and hidden from Spotlight by default. Originals can be deleted after ingest
- Settings belong to each slide (each use of an item), never to the library item
- Editing means removing and reordering slides; the output order list is drag and drop
- Library delete: Delete asks first, and ⌘Delete moves to the Trash without
  asking (the Photos convention)
- Removing a slide from a show: a one-time alert ("not moved to the Trash")
  with the standard "Do not show this message again" checkbox
- Batch rename is modelled on Finder's Rename Items; an Info panel shows
  metadata and holds tags
- Tags live in the database; writing them as Finder tags is a checkbox, off by default
- Photos-library permission: deferred until the app has taken shape
- Manifest: one-line-per-slide TSV (see Phase 4). Chosen for shows of 50 to
  several hundred slides. (2026-09-22: kept as the readable half; `show.json`
  now carries the whole show. See Phase 4)

- Spotlight: the library is hidden by default (`.noindex`). Preferences has
  a setting to let Spotlight index it

## Open questions

Plan approved 2026-09-20; Phase 2a added and settled 2026-09-21. The live
list is in `spec/status.md` → Open questions; image stickiness (the end of
Phase 3) is the one still open here.
