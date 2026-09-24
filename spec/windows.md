# Windows of their own — the edit suite inside the edit suite

**Status:** Planned: a vision, not yet designed (Jason, 2026-09-24).
Nothing is built. **Left:** everything. The open questions come first,
then a design with Jason.

Names follow `spec/anatomy.md`.

## The idea

The main window holds everything, and everything takes space in it. Many
of its areas should also work **in a window of their own**, and leave the
main window when they do:

- the collections list, popped out and dragged next to where files are
  being dropped from;
- the library as a list window, for the same reason;
- the edit zone as a tool window of its own;
- a single row opened in a window, larger, to edit it more easily;
- a slide opened by double-click in a large editor in front of
  everything, to work on that slide alone.

In Jason's words: "a mini edit suite inside the edit suite". It will
change as it meets real use.

## Two kinds of window

The difference Jason drew: some windows are **the area itself**, moved;
others are **one thing, opened up**.

### 1. Areas that can leave the main window

A whole area, the same one that's docked in the main window, living in a
window instead. There's one of each. It's listed in the **View or Window
menu**, and it can be put back.

| Area | Why in its own window |
|---|---|
| **Sidebar** (collections and shows) | Next to Finder or Photos, as a drop target |
| **Library** as a list | The same, and as a source to drag from while Edit Show fills the main window |
| **Browser** | Its files beside the edit zone on a second screen |
| **Inspector** | Settings where they're wanted, and the columns get its width back |
| **Viewer** | Already done: the pop-out viewer (`Player.popOut`) shares the viewer's playback |
| **Edit zone** | The rows full width, on their own screen |

### 2. Editors for one thing

Opened *from* the thing, by double-click or a context menu. They aren't
in the View or Window menu, because each one is about a particular slide
or row, not a place in the app. There can be several, and they close
when done.

- **A row, opened up:** one row (say the music row, or the images row) in
  a window, taller and with more room, for detailed work.
- **The Slide Editor** (working name; Jason's first word for it was
  "deep edit window"):
  - Double-clicking a slide opens it: a large view of **that slide
    alone**, in front of everything, with its settings around it.
  - The viewer shows the sum of every layer at the playhead. The Slide
    Editor shows one slide and nothing over it, so its details can be
    worked on without fighting the rest of the show.
  - **This is where the collage maker lives** (plan, Later: the gradient
    mask between two photos, and multi-panel slides). A collage is one
    slide built from several images, which is exactly what the Slide
    Editor is for.
  - Its relation to the inspector: the inspector is the quick version,
    always there. The Slide Editor is the deep one, opened on purpose.

## The edit zone

**The edit zone** is the unit that holds the rows: the transport, the
ruler and the rows under it. That's the thing that could be a tool window
of its own. (`spec/anatomy.md` had called ruler plus rows "the timeline";
the edit zone is that plus its transport, since zoom, snapping and the
range belong with the rows wherever they go.)

## What already exists to build on

- **Floating panels that share the main window's undo:** the Info panel
  and the Rhythm tool are AppKit panels hosting SwiftUI, whose
  `undoManager` is overridden to the main window's
  (`InfoPanelWindow.sharedUndoManager`). ⌘Z in them undoes the same
  history. Every detached area would need this: a separate window's undo
  manager isn't the main one's, and ⌘Z asks the *key* window's
  (showtools-gotchas).
- **A view of shared playback in another window:** the pop-out viewer
  shows an engine the main window owns. Closing it leaves playback
  running.
- **Following the show on screen:** the Rhythm tool follows whichever show
  is selected, which is how a detached browser or edit zone would behave.
- **In-app drags between windows:** `ItemDrag` carries library ids, so a
  drag from a detached library or collection list into the edit zone
  works as it does now within one window.

## What stands in the way (from the code, before any design)

- **The show's editing state lives inside views.** The slide selection is
  `@State` in `ShowView`. The lane, song and marker selections, the
  engine and the zoom are `@State` in `EditShowView`, which also creates
  the engine on appear and shuts it down on disappear. A browser or edit
  zone in another window can't reach any of that.
  **The prerequisite for all of this:** move it into one shared object
  per open show (a "show session": selection, engine, zoom), owned by the
  model rather than by a view. The screen wouldn't change, and it would
  also make the audit's menu work (`spec/hig-audit.md` batch 5) simpler,
  since menus need the same state.
- **Keys are per window.** `SingleKeys` (J/K/L, Space, I/O…) is a monitor
  on one window, and menus read focused values from the key window. A
  detached edit zone needs its own, so Space still plays when it's the
  key window.
- **The columns assume their members.** `ColumnsSplitView` already hides
  the inspector. Taking the browser or the viewer out as well means it
  must lay out whichever columns remain.
- **Window APIs and the layout-loop crash.** The crash was SwiftUI's
  `.inspector()`. New windows should follow the Info panel's pattern (an
  AppKit window hosting SwiftUI) rather than new SwiftUI scene or
  inspector APIs, until a harness says otherwise (CLAUDE.md: check AppKit
  layout in a harness first).

## Open questions (for Jason)

1. Which comes first? The Slide Editor adds something new without moving
   anything. The detachable areas change what the main window is.
2. Does a detached area follow the show on screen (as the Rhythm tool
   does), or stay with the show it was opened from? Could two shows be
   open at once?
3. Floating panel (always over the main window) or ordinary window (can
   go behind it)? It may differ by area: an inspector wants to float, an
   edit zone on a second screen doesn't.
4. Does the app remember which areas are detached, and where, between
   launches?
5. When an area leaves, does the main window close up the space, or keep
   a slot to put it back?
6. The Library as a list: a second view of the same grid (with a
   list/grid switch), or a separate small window?
7. **Double-click on a slide:** today it toggles the inspector (Edit
   Slides) or opens it (Edit Show). The audit's G3 asks which. If
   double-click opens the Slide Editor instead, G3 is settled a
   different way.

## A possible order (not a plan)

1. **The show session:** state out of the views. It changes nothing on
   screen, it's worth doing for the menus anyway, and nothing else here
   is possible without it.
2. **The Slide Editor,** as the first new window. It's additive, and it's
   the home the collage maker needs.
3. **One detachable area,** probably the inspector or the browser, to
   prove the pattern (undo, keys, the columns closing up). Then the
   others.
4. **The edit zone, detached,** last: it carries the most keys and
   playback.
