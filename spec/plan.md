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
- Not a video editor. There's no multi-track compositing, titles or colour grading.

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
| fit         | fill / fit / stretch |

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

### Phase 2: Composer
- **Slide list panel (the output order):** thumbnails in play order, drag and
  drop to reorder, multi-select, remove, duplicate. You can also add the same
  library item again
- **Removing a slide** (Delete) takes it out of this show only. The first
  time, a standard macOS alert explains that the image is **not** being moved
  to the Trash and stays in the library. The alert has the system's own
  "Do not show this message again" checkbox (`NSAlert`'s suppression button,
  the one AppKit provides for exactly this case), and once it's ticked,
  removals happen silently. ⌘Z undoes a removal
- **Inspector panel:** edit the selected slide(s). Editing several at once is
  allowed, and fields that differ show as "mixed"
- **Ken Burns editor:** drag the start and end frame rectangles directly on the image
- Preview a single slide with its transition in and out

### Phase 2b: Library manager
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
- Add a song and draw its waveform on a timeline
- Slides appear as blocks under the waveform. Dragging a block's edge changes
  that slide's length
- **Alignment aids:** markers you drop yourself while listening (tap a key on
  the beat). Slide edges snap to markers. Automatic beat detection may come
  later if the markers turn out to be a chore
- Scrubbing the timeline scrubs the show

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
- Beat detection
- Photos-library browsing inside the app. Deferred until the app has taken
  shape; the permission question gets worked out then. Drag-and-drop from
  Photos works from Phase 1 regardless

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

None. Plan approved 2026-09-20.
