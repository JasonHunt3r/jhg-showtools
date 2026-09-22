# ShowTools — plan

Approved 2026-09-20.

## What it is

A slideshow composer and player for macOS. You get as much control as possible
over each slide: how long it shows, which transition it uses, its Ken Burns move,
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

- SwiftUI app with AppKit underneath, built with SwiftPM and wrapped into a
  `.app` by a shell script. No Xcode project.
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

A library item carries **no** slide settings. Length, transition and Ken Burns
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
| Ken Burns   | off, or a start frame and end frame (position and zoom), plus easing |
| fit         | fill / fit / stretch. New shows default to **fit** (changed from fill 2026-09-21) |
| transform   | the still placement on top of fit: offset, scale, rotation, anchor (Final Cut's Transform). Always there; the identity leaves the image where fit puts it (added 2026-09-21) |

Every field that can inherit does so until it's overridden. Changing the show's
default updates every slide that hasn't been given its own value.

### Video-export hook (built in from day one)

All rendering goes through one function: **"what does the screen look like at
time *t*?"** That covers which slide(s) are on screen, how far the transition has
got, and where the Ken Burns frame is. The live player, the timeline scrubber and
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
  Ken Burns (show default Off/Auto; per-slide Off/Auto)
- Keyboard: space, ← →, Home/End, type a number + ↩ to jump, F, Esc
- **Changed from the draft:** shows are stored in the library database, not
  as separate document files. They save on every edit. They need to be in
  one place anyway so that "random show" can find them all.
- **Not yet:** ⌘Z undo (comes with the Phase 2 composer), a custom Ken Burns
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
- **Both modes:** multi-select editing shows "mixed" values; a **Ken Burns
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
  shows through. Ken Burns and Rotation add motion on top of the Transform
- **Inspector layout (settled 2026-09-21):** **Transform** (position,
  zoom, rotation) sits at the top of the column. It's the image's starting
  state. Below it is everything time-based: the transition in, Ken Burns,
  and animated Rotation. Jason counts animated rotation in that camp. The
  on-image handles edit the Transform; they never switch a motion effect on
- **Onion skin** (built 2026-09-21, not for video slides yet). While you frame slide B, slide A's **last frame** is drawn
  semi-transparent over it (an opacity slider and a toggle). It's an editing
  aid only and never renders into the show. It shows A's end frame exactly as
  it plays, including Ken Burns and rotation
- **"Soft at this zoom" flag** (built 2026-09-21: an orange triangle in the
  order list and on the storyline block, a line in the inspector, and the
  exact figure in the block's hover info; flagged above 1.25× the file's
  pixels on the main screen, at the slide's closest moment). When the framing shows the image with fewer
  pixels than the output, the slide gets a warning. This is where the
  upscaling hook later attaches (see the plugin seam)
- **Effects stack per slide (mix and match).** Each slide *use* can have
  several motion effects on at once, each with its own on/off checkbox in
  the inspector. Ken Burns (pan and zoom) and rotation are separate effects
  that combine. 2a's effects: **Ken Burns** and **Rotation**. The stack is
  also where later effects plug in
- **Rotation**, which works with Ken Burns or on its own. It has its **own
  interface** (its own inspector section and its own on-image editor: built
  2026-09-21 as the preview's Rotation mode, with green start and red end
  outlines, an arm per end to turn it, and pivot crosshairs), and
  it isn't folded into the Ken Burns editor (settled 2026-09-21). It has two modes,
  chosen per slide:
  - **Speed:** a speed slider (°/s). Note that trimming the slide then
    changes where the rotation ends, which moves a match-cut end frame
  - **Angles:** a start angle and an end angle, so the end frame stays put
    when the slide is trimmed. This is the mode for match cuts
  - **Acceleration** is a slider with **0 in the centre**: left decelerates,
    right accelerates. In Angles mode it shapes the way from start to end
    rather than changing the end angle
- **Ken Burns gets the same acceleration slider** (settled 2026-09-21),
  alongside its current easing, so a Flush can speed up its zoom as well as
  its spin
- **Pivot ("polar deviation").** The rotation point can be offset from the
  image centre. Two small polar grids (a joystick for start and one for
  end), with a **Lock** checkbox that keeps them the same. The pivot is
  pinned to the image, so it moves along with a Ken Burns pan
- **Transform handles on the image (Adobe conventions,** checked against
  Adobe's Photoshop help 2026-09-21). They act on whichever frame, start
  or end, is selected. The Ken Burns editor gets the scale handles; the
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
  image (Ken Burns, Rotation), **off by default**. When it's on, the effect
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
thing acting on the picture (transition in and out, Ken Burns, Rotation,
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

### Phase 3: Music + timeline
(Decisions from Jason, 2026-09-21, unless marked otherwise.)
- **Modular rows.** Every timeline row (transitions, images, slides, music)
  is a module, and the rows can be dragged into any order. Each row has a
  small **header** at its left end (like Logic's track headers, which Final
  Cut doesn't have). You grab the header to move the row, and it holds the
  row's controls. Reordering is built in this phase, not later.
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
  restarts after its longest row ends.
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
- **The range:** I and O set in and out points, drawn as two blue markers
  on the ruler with the span between them shaded (Final Cut's convention).
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
  **"Fit slides to markers"** checkbox also re-cuts the slides in the range
  so their cuts land on those markers.
- **Rhythm patterns**, three ways to write the same thing:
  - **text**, a short pattern repeated to fill the range, e.g.
    `w w h h q q 3e 3e 3e` (whole, half, quarter, a triplet of eighths)
  - **musical notation**: the pattern drawn as notes, with note buttons
    that write it for you
  - **a step grid**, like a drum machine: squares for one bar, clicked
    where a slide should change
  - plus a **note-length multiplier**: how many beats a whole note stands
    for, so the pattern can be slow enough for pictures (a quarter note on
    every beat would be a slide every half second)
- A note's value only sets the gap from one slide change to the next.
  "Staccato" was colour, not a literal feature. It did spark an idea for a
  **strobe effect**, which is parked under Later.

### Phase 3b: Duplicate finder
- **Exact duplicates:** identical content, found by hash. This is instant
- **Near duplicates:** the same picture resized, recompressed, or saved in
  another format. Found with Apple's Vision framework (an image "fingerprint"
  comparison), with a similarity slider
- Results show side by side, grouped. The app suggests a keeper (largest
  resolution) and you confirm. Shows that used a removed copy are pointed at
  the keeper, so nothing breaks

### Phase 4: Setlist export / import
- **Export:** copy the source media into a folder, renamed in show order
  (`001_originalname.jpg`, `002_…`). The number is padded to fit the slide
  count, so a 1,200-slide show gets `0001_`, which keeps Finder's order right.
  The folder also gets a `show.tsv` manifest
- **Manifest format:** tab-separated text, **one line per slide**, with a header
  row. It's built to stay usable at several hundred slides: you can scan it,
  it opens directly in Numbers or Excel for bulk edits, and it's trivial to
  parse back in. Show-wide defaults go in `#` lines at the top. An empty cell
  means "use the default", so a mostly-default show stays short and readable:
  ```
  # ShowTools setlist v1
  # default_length	5.0
  # default_transition	dissolve 1.0
  # music	song.m4a
  file	length	transition	kenburns_start	kenburns_end	fit
  001_beach.jpg	8.0		0.5,0.5,1.0	0.3,0.4,1.4
  002_sunset.jpg		swipe-left 0.5
  ```
- **Import:** open an exported folder and the show is rebuilt from the manifest.
  If the manifest is missing, it falls back to plain file order with default settings
- The originals are never renamed or moved. Export only ever writes copies

### Phase 5: Live desktop
- One borderless window per monitor at desktop level, behind icons and all
  other windows, on every Space
- **Per monitor:** pick a show, and a play mode:
  - **No randomization**: the chosen show, in order, as composed
  - **Random from show**: the chosen show's slides, shuffled
  - **Random show**: the app picks one of your shows and plays it in order
  - **Random from all files**: slides shuffled from the whole library
- **"All same" checkbox:** every monitor plays the same thing. With a random
  mode, the random pick is made once and mirrored to every monitor. With the box
  unchecked, each monitor makes its own random pick
- Detects monitors being plugged in or unplugged and reassigns shows as they come and go
- Videos and GIFs *can* play here (it's a real window, not a wallpaper image).
  There's a setting to limit this to still images to save power
- A fallback option that sets the real system wallpaper per monitor (still
  images only, with no transitions)

### Later
- Video export (the hook above)
- ~~Beat detection~~ (moved into Phase 3, 2026-09-21)
- **A strobe effect** (Jason, 2026-09-21): a slide flashing on and off
  against the background colour. Came out of the rhythm-pattern talk
- Photos-library browsing inside the app. Deferred until the app has taken
  shape; the permission question gets worked out then. Drag-and-drop from
  Photos works from Phase 1 regardless
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
  Random show plays the picked show in order; random from show shuffles it
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
  several hundred slides

- Spotlight: the library is hidden by default (`.noindex`). Preferences has
  a setting to let Spotlight index it

## Open questions

None. Plan approved 2026-09-20; Phase 2a added and settled 2026-09-21.
