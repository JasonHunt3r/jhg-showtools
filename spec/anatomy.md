# Anatomy — the window, its areas, and how they nest

**Reference.** What each part of the app is called, what it's for, what
it holds, and what it affects. `spec/layout.md` maps the *code* (which
file owns what); this maps the *screen*. Read it before designing
anything that adds, moves or connects an area, and use its names in
specs, commits and conversation.

Written 2026-09-24 from the code at `0250aee`, in a cloud session, so
nothing here was checked on screen. Where the code and what Jason sees
disagree, the screen wins, and this should be corrected.

## 1. Names

One name for each thing. The **Name** column is the one to use. **Also
called** lists names in the code or in older specs, which mean the same
thing.

### Things you make (the data)

| Name | What it is | Also called |
|---|---|---|
| **Library** | Every file ShowTools has taken in, in one folder on disk. One is open at a time. | master library (the default one) |
| **File** | One picture, animation, video or audio file in the library. Has a name, a rating and tags, and **no slide settings**. | item, `MediaItem` |
| **Collection** | A named group of files. Every show belongs to one. | `MediaCollection`; Final Cut's Event |
| **Show** | A slideshow: slides in order, plus lane images, audio clips and markers, and the show's defaults. | project |
| **Slide** | One *use* of a file in a show, with its own settings. The same file can be several slides. | use, block (in the storyline) |
| **Audio clip** | An audio file placed in a show's audio row: music, a recording, any sound. Never a slide. | song (the old name), `AudioClip`, `show.music` |
| **Sound** | A video slide's own sound, set in the inspector and on its block. Not an audio clip. | `settings.audio` |
| **Lane image** | A picture laid over the show for a stretch of time, independent of the slides under it. | overlay, `OverlayClip` |
| **Transition** | How one slide gives way to the next. Belongs to the slide it leads *into*. | transition in |
| **Marker** | A point in the show's time: placed by hand (M), or detected from an audio clip's beats. | detected marker |
| **Range** | A stretch of time set with I and O, for looping and Listen. | in/out |
| **Show defaults** | Length, transition, Pan and Zoom, fit, background and loop for every slide that doesn't set its own. | defaults |

### Places on screen

| Name | Where | Also called |
|---|---|---|
| **Main window** | The one window with the Library pane | |
| **Library pane** | Left column: the Library row, then Collections with their Shows. Called **the Library** for short | sidebar (the old name), source list |
| **Detail** | Everything right of the Library pane. Shows one of: the grid, or a show in one of two modes | |
| **Library grid** | Detail, when the Library or a collection is selected: tiles of files | the grid |
| **Filter bar** | Top of the grid: Search, Filter, Sort, Similar | the bar |
| **Edit Slides** | A show's list mode | |
| **Edit Show** | A show's timeline mode | |
| **Defaults bar** | Top of Edit Slides: the show's name and defaults | |
| **Slide list** | Edit Slides' list of slides | order list (old) |
| **Inspector** | Right column in both modes: the selected slides' settings | |
| **Viewer** | Edit Show's top-left column: the picture, and the frame strip under it | preview, work area, stage |
| **Frame strip** | Under the viewer: rendered frames of the finished show | |
| **Browser** | Edit Show's middle column: the show's collection, uses first | Collection Browser |
| **Timeline pane** | The bottom of Edit Show: the unit that holds the rows, meaning the transport, ruler and rows together. "The timeline" for short. Detached, it would be the **Timeline window** (`spec/windows.md`) | edit zone (Jason's first word), storyline (`StorylineView` draws it) |
| **Transport** | Top of the timeline pane: play, clock, toggles, zoom | transport row |
| **Storyline** | The slides row alone, as in Final Cut's primary storyline | |
| **Ruler** | Top of the timeline: time, the range, markers, the playhead | |
| **Row** | One horizontal band of the timeline. There are four kinds (below). | track, lane (loosely) |
| **Lane** | The transitions row and the images row together (Phase 2c's name) | |
| **Row handle** | The grip at a row's left: drag to reorder rows, click for its drawer | |
| **Drawer** | A row's settings, along the timeline pane's left side. It slides out over its row. Empty today. Planned: icon buttons at its left edge, and a left handle that sets how much of the drawers shows (`spec/windows.md`) | prefs drawer |
| **Edge handle** | *Planned.* The thin, visible grip a pane leaves on the window's edge when it's closed: drag to open or resize, double-click to open or close (`spec/windows.md`) | handle bar |

"Layers" is used only for how the picture is built up (§4), never for
rows. That keeps "row" for the timeline's bands, and "layer" for what's
drawn on top of what.

**The left pane is the Library pane (Jason, 2026-09-24),** "the Library"
for short. It was "the sidebar", which names a position, not a thing:
the browser and the inspector are sidebars too, when open. "Pane" sets it
apart from the **library panel**, the floating window it can launch.
Older docs and the code (`SidebarItem`, `model.sidebar`) keep the old
word. "Sidebar" is still right for Apple's own things: the Mac's
translucent sidebar look, and the Show Sidebar menu item.

**A map to print (planned, on hold until the terms are settled).** PNGs of each view with every area labelled
by its name here: a map to point at when saying where something should
be or how it should work. Schematic versions can be drawn from this file
(the container has a browser engine that can render them). Labelled
screenshots of the real app need Jason's Mac.

**Areas and editors** (`spec/windows.md`, planned): an *area* is one of
the places above that could move into a window of its own and back. An
*editor* is a window opened on one thing, such as a row or a slide (the
Slide Editor).

## 2. The nesting

```
Main window
├─ Toolbar                       (changes with the detail: grid tools, or show tools)
├─ Library pane
│   ├─ Library
│   └─ Collections
│       └─ Collection  ▸  its Shows
└─ Detail  — one of:
    ├─ Library grid              (Library or a collection selected)
    │   ├─ Filter bar
    │   └─ Tiles                 (or, with Group Similar, groups of tiles)
    └─ Show                      (a show selected) — one of two modes, one selection shared:
        ├─ Edit Slides
        │   ├─ Main column
        │   │   ├─ Defaults bar
        │   │   └─ Slide list
        │   └─ Inspector
        └─ Edit Show
            ├─ Columns
            │   ├─ Viewer
            │   │   ├─ Picture   (with its layers, §4)
            │   │   └─ Frame strip
            │   ├─ Browser
            │   └─ Inspector
            └─ Timeline pane
                ├─ Transport
                └─ Timeline
                    ├─ Ruler     (time, range, markers, playhead)
                    └─ Rows      (the show's own order; default below)
                        ├─ Images row        ┐ the lane
                        ├─ Transitions row   ┘
                        ├─ Slides row        (the blocks)
                        └─ Audio row
```

**Around the main window:**

- **Player:** a window, or full screen, that plays a show. It has its
  own keys (Space, ←/→, J/K/L, Home/End, a typed number then Return).
- **Pop-out viewer:** the viewer's picture in its own window, sharing the
  viewer's playback (for a second screen).
- **Info panel:** a floating panel, Get Info on files, following the
  grid's selection. It shares the main window's undo.
- **Rhythm tool:** a floating panel for the show on screen. It follows the
  show if another is selected, and shares the main window's undo.
- **Sheets:** Batch Rename, Keep One, Detect Beats, Place Image Here
  (a library picker), and the export panels.
- **Settings:** the app's settings window.
- **BGTools:** a separate app inside ShowTools that plays shows on the
  desktop. It only reads the library. See `spec/bgtools.md`.

## 3. Each area: what it's for, what it holds, what it affects

### Library pane

- **For:** choosing what the detail shows.
- **Holds:** the Library, collections (each opens and closes), and their
  shows. Badges count files or slides.
- **Takes:** a drop of files onto a collection adds them to it; onto a
  show, appends them as slides.
- **Affects:** replaces the whole detail. Switching shows clears the
  slide selection.

### Library grid

- **For:** finding, sorting and managing files, and starting shows and
  collections from them.
- **Holds:** the files of the Library or of one collection, filtered by
  the filter bar. Group Similar or Show Similar rearranges them.
- **Selection:** its own set of files. It isn't shared with any show. The
  Info panel follows it.
- **Delete:** in the Library, asks, then moves files to the Trash. In a
  collection, takes them out of the collection. ⌘Delete in either moves
  them to the Trash.

### A show, in either mode

- **One slide selection, shared by both modes.** Switching mode keeps it.
  Switching show clears it.
- **One inspector, one toggle** (⌥⌘I, `inspectorShown`). It's shown or
  hidden in both modes at once.
- **One undo history:** the main window's. Every show edit goes through a
  `ShowMutator` with an undo name.

### Edit Slides

- **For:** the show as a list: order, and per-slide settings, without
  the timeline.
- **Defaults bar:** the show's name and defaults. **This is the only
  place show defaults can be changed.** Edit Show has no way to reach
  them.
- **Slide list:** a numbered row per slide, showing its length,
  transition and Pan and Zoom. What a slide sets itself is shown in the
  accent colour, and what it inherits is shown grey. Drag rows to
  reorder. Double-click toggles the inspector.
- **Has no picture.** Nothing plays in place. Play opens the player.

### Edit Show

- **For:** the show against time: seeing it, timing it, layering it,
  scoring it.
- **Viewer:** the picture at the playhead, drawn live.
  - Click a slide's image to get its Transform handles, or its Rotation
    handles.
  - A selected lane image or transition gets its settings as a **bar
    over the picture**, not in the inspector.
  - The corner controls are work-area zoom, onion skin and pop-out.
  - The frame strip shows the finished result; the timeline shows the
    parts.
- **Browser:** the show's collection. Uses of files come first, then
  files not in the show.
  - Picking a use selects it in the show, and the show's selection shows
    back here.
  - With the browser focused, E appends, W inserts at the playhead, and
    Q places a lane image at the playhead.
- **Inspector:** the same as Edit Slides', plus live preview. Sliders
  draw in the viewer as they move and save once, on release.
- **Transport:** previous slide, play, next slide, the clock, and the
  shuttle rate.
  - Toggles: Snapping (N), Range, Range lines, Marker lines, and Loop
    (⌘L).
  - Zoom out, zoom in, and fit (⇧Z).
- **Timeline:** the rows under the ruler, sharing one clock with the
  viewer. A click here gives the timeline the keyboard.

### The rows

Each row is one kind. A show has one of each, in its own order, which is
saved with the show. The default order is images, transitions, slides,
audio.

| Row | Holds | Its own selection | Edits |
|---|---|---|---|
| **Images row** | Lane images, placed in time, with a level line for opacity and fades | one lane image | drag to move, trim the ends, drop files in, right-click the empty row for Place Image Here… |
| **Transitions row** | A section at each cut, as wide as the transition | one transition | drag the body or ends for timing, + on hover at a cut to add one |
| **Slides row** | A block per slide, as wide as it's long, magnetic (no gaps) | slides (shared with Edit Slides) | drag to reorder, trim or roll at cuts, a video's volume line |
| **Audio row** | Audio clips, with waveforms and a volume/fade line | one audio clip | drag to move, trim, overlap to crossfade, Detect Beats… |

**What the row order does and doesn't do:** it changes **where rows sit
on screen, and nothing else.** It does not change what's drawn on top of
what in the picture: lane images are always over the slides (§4),
whatever the rows' order. That's a trap for a new user who drags the
images row under the slides row expecting the images to go behind. It
will matter more if a show can ever have two rows of one kind (a
second images row: plan, Phase 3).

## 4. The picture's layers

What the viewer, the player, the frame strip, BGTools and a movie export
all draw, bottom to top. Everything goes through
`ShowTimeline.frame(at:)` → `Compositor.compose`, so all five agree.

```
5  Lane image        the one lane image at this moment, faded and blended   (images row)
4  Incoming slide    during a transition: the next slide, per the style     (transitions row)
3  Slide             placed by fit → Transform → Pan and Zoom → Rotation    (slides row)
2  Slide background  a slide's own colour, if it sets one
1  Show background   the show default: behind everything, and after the last slide
```

Only in the viewer, on top of those (never saved into the show, and
never exported):

```
   Bar               a selected transition's or lane image's settings
   Corner controls   work zoom, onion skin, pop-out, play/pause
   Handles           Transform or Rotation, on the selected slide's image
   Onion skin        the previous slide's last frame, over the selected image
   Pasteboard        the grey round the picture when work zoom is below 1
```

Audio clips have no layer. They're heard, not drawn. A video slide's own sound
mixes with them.

## 5. What affects what

### Selection in Edit Show

Only one *kind* of thing is selected at a time: selecting slides, a lane
image, a transition, an audio clip or markers clears every other kind. Several
slides or several markers can be selected at once; lane images,
transitions and audio clips are one at a time.

| Selected | Its settings show in |
|---|---|
| slides (from the timeline, the browser, or the viewer's image) | the **inspector** |
| a lane image | a **bar over the viewer** |
| a transition | a **bar over the viewer**; selecting one also pauses and moves the playhead to it |
| an audio clip | *nowhere*: its level line and context menu only |
| markers | *nowhere* |

**Delete** acts on the first of these it finds selected: markers, then
the audio clip, then the lane image, then the transition (leaving a cut), then
slides. **Esc** closes open drawers first. Otherwise it clears lane
image, audio clip and markers, but not slides or a transition.

### Other links

- **Browser ↔ timeline:** picking one use selects that slide (or lane
  image), and the timeline's selection picks it back. Each side changes
  the other only when they differ.
- **Slide selection → viewer:** clicking a block moves the playhead to
  that slide and pauses.
- **Inspector → viewer:** slider drags draw live, and are saved on
  release as one undo step.
- **Timeline zoom and scroll → frame strip:** the strip follows the
  timeline's zoom and scroll, so frames sit over their moments.
- **Playhead ↔ everything:** the viewer, timeline, frame strip, transport
  clock and pop-out share one engine and one clock. When audio clips play,
  the audio player (`MusicPlayer`) *is* that clock.
- **Show defaults → every slide:** a slide that doesn't set a value
  inherits it. The slide list shows which is which by colour.
- **Grid selection → Info panel:** the panel shows what's selected in the
  grid.
- **The show on screen → Rhythm tool:** the tool follows the show on
  screen.

### What the app remembers between launches

These are view settings, saved in the app's preferences (`@AppStorage`),
not with the show:

- **The mode and panels:** `editMode`, `inspectorShown`,
  `frameStripShown`, `frameStripHeight`, `frameStripSpan`.
- **Edit Show's views:** `storylineZoom`, `workZoom`, `onionSkin` and
  `onionOpacity`, `snapping`, and the columns' widths (`EditShowColumns`).
- **The grid and browser filters:** `grid*`, `browser*`,
  `similarWithin`.
- **The Rhythm and Detect Beats tools:** `rhythm*`, `beat*`.

These live in `com.jhg.showtools`, which test copies share: see
CLAUDE.md.

The row order, the range, the loop state and the lines are the other
way round. They're saved **with the show** (its editing state), so they
come back with it.

## 6. Asymmetries worth knowing

These follow from the structure. Each is a candidate for
`spec/hig-audit.md` §G rather than a rule:

- Show defaults can only be changed in Edit Slides (§3).
- Transition and lane image settings sit over the viewer. Slide settings
  sit in the inspector. Audio clips and markers have no settings panel at all.
- The inspector's Effects timeline and a video slide's Sound are drawn for
  the *first* selected slide only. Everything else in the inspector
  applies to every selected slide.
- A drop onto the slide list appends; a drop onto the timeline inserts
  where it lands.
