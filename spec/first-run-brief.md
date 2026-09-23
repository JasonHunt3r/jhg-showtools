# ShowTools: guided first run, a brief

For fleshing out with App Claude (Jason, 2026-09-22). Nothing here is built
or decided yet beyond what's marked as Jason's.

## What ShowTools is

A macOS slideshow composer and player for Jason's own Mac (SwiftUI and
AppKit). You get as much control as possible over each slide: how long it
shows, its transition, its movement, and how it lines up with music. It
plays in a window, full screen, or live on each monitor's desktop.
Timelines follow Final Cut Pro's conventions.

## How things are organised (Jason's words, 2026-09-22, first time stated)

"Your library contains all of your images. You can sort these images and
organize them into collections, and using a collection you can create a
highly customizable slideshow by adjusting the transform controls and
applying effects to your slides. Also its music files."

As built:
- **Library**: every file ShowTools has taken in (photos, animated GIFs,
  videos, songs). Importing *copies* files in, so originals can be deleted.
  Files carry a rating and tags, never slide settings. You can have more
  than one library (File ▸ Open Library…).
- **Collection**: a set of the library's files. A file can be in several.
  A new library starts with one called "Untitled Collection".
- **Show**: belongs to a collection and draws its pictures from it. It has
  default settings (slide length, transition, fit…), slides, songs, and
  markers.
- **Slide**: one *use* of a file in a show, with its own settings: length,
  transition in, Ken Burns (a pan and zoom), fit, transform (position,
  scale, rotation), background, rotation effect. The same photo can be
  several slides with different settings. Anything not set uses the show's
  default.
- **Songs**: library files too, placed on the show's **music row**; they
  can carry beat markers, and set the show's clock while playing.

## Where things are on screen (the places a first encounter could happen)

- **Sidebar**: Library, then collections, each holding its shows.
- **Library / collection grid**: thumbnails; Delete, Get Info, Find Similar.
- **Info panel** (⌘I): a file's details, rating and tags.
- **A show** has two modes:
  - **Edit Slides**: a detailed slide list and the inspector.
  - **Edit Show**: a large live preview, the transport, and the
    **storyline** (slides as blocks, width = length) with a **lane** above
    it (a transitions row across the joins, and an images row for pictures
    layered over slides), the music row, markers, and the collection's
    files in a column on the right.
- **Inspector** (⌥⌘I or double-click a slide): the slide itself, then an
  **Effects** section (a small timeline of what acts on it, then the
  controls).
- **Rhythm panel** (⌘R): rhythm patterns for placing slides on the beat.
- **Export Show… / Import Show…**: a show as a folder of numbered files,
  plus `show.json` and `show.tsv`.
- **Export Movie… (⇧⌥⌘E)**: the show as a real movie file — picture,
  music, and video slides with their own sound.

## What exists now

Plain empty states: "Your library is empty" (with an Import… button),
"“Name” is empty" for a collection, "No slides yet" for a show, "No slide
selected" in the inspector, "No Selection" in the Info panel.

## Jason's sketch

- **Not a separate tutorial.** Each *first encounter* teaches itself, and
  one step leads to the next.
- **Welcome**: when everything is empty, a welcome version of the empty
  library, whose button adds images.
- **First empty collection**: a fuller version explaining what you're
  looking at, with **Rename this collection** (default name maybe "My
  First Collection"); once renamed, that button goes and **Import** is left.
- **Inspector, first opened**: a cover over it, "This is the inspector,
  it's for…", with **Got it**. That closes the window if no file is
  selected, or uncovers the info of the file whose click opened it.
- **Afterwards**, empty places say something plain, as now.
- The lingo (slide especially) is introduced along the way, spread over
  these encounters, not all at once.

## Apple's guidance (HIG, Onboarding; checked 2026-09-22)

- People learn better by doing the task than by viewing instructions:
  make it interactive where possible.
- Put tips in context, next to the part of the interface they're about,
  one task at a time.
- A separate tutorial should be optional, not shown again once skipped,
  and easy to find later (Help or Settings).
- Apple's TipKit shows a tip once and remembers its dismissal: a possible
  engine for "first encounter" covers.

## Open questions to settle

1. The list of first encounters, and their order (library, collection,
   show, Edit Show, inspector, music row, lane, Rhythm panel…).
2. What each one says, and which button it offers.
3. What "first" means: per Mac (preferences) or per library.
4. Skipping all of it, and seeing it again (Help ▸ …?).
5. The words themselves: a short glossary (library, collection, show,
   slide, song, transition, Pan and Zoom, transform, effect, lane,
   storyline).

**Naming, settled 2026-09-22:** the effect is called **Pan and Zoom**, not
Ken Burns — the old name is a reference rather than a description. The app
has not been renamed yet (`spec/status.md` has the job), so the UI you see
today still says "Ken Burns" everywhere. Write the onboarding words with
**Pan and Zoom**.
