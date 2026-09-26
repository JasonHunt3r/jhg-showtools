# ShowTools — status

**Read this first each session.** The state of play, in the present tense.
Rules are in `CLAUDE.md`, decisions in `spec/plan.md`, and what happened on
which day in `spec/history/` (never read for current rules). This file is
rewritten, not appended to: if a line has a date and a story, it belongs in
`history/`.

Repo: `~/Projects/ShowTools`, pushed to **github.com/JasonHunt3r/jhg-showtools**
(public, `main`).

## Where it stands

**Everything planned is built**, including Groups inside collections and
the range package (below). Phases 1–5, Phase 3b, Phase 4 and video
export. **337 tests** (324 core + 13 BGTools). **Library schema 14.**

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
| E Video export | Built, E1–E5. Own spec `spec/video-export.md`. Listened to by Jason (2026-09-25) |
| 5 BGTools | Built, B1–B7, plus naming screens/the map view/the window opening on your screen (2026-09-25). Own spec `spec/bgtools.md`. Left: its own "Next up" list (items 23–25, after the ShowTools fixes), Jason's hands-on pass, the Pan and Zoom cost, telling BGTools when a library moves |

Every schema upgrade is additive and tested by opening a library of the
version before (7 rows, 8 music, 9 markers, 10 editing state, 11 rhythm
patterns, 12 their note length, 13 groups, 14 a drag order for a
collection's/group's files). Before an upgrade the database is copied
to `Library.sqlite.v<N>.bak`. Video export needed no schema change: a video
slide's level line is slide settings, which are JSON.

`~/Applications/ShowTools.app` was last reinstalled 2026-09-25 20:28,
at `c7d657e`: the rebuilt drag-to-reorder, the pile, edge scrolling and
the Undo fix. Reinstalled again after `79ca4e0` (Escape put-back, the Library's sort
strip), and at 23:04 at `71aa2a1` (items 13 and 30). **Reinstalled
2026-09-26 at `464e8c5`**: item 20, the browser deselect fix, the inspector
bar's right-click, and the "No menu yet" notes are all in it.
Reinstalling stops the real BGTools instance (`install.sh`'s own quit
sequence); BGTools wasn't restarted after the 20:28 install. BGTools'
desktop extension (`BGToolsControls.appex`) was also killed before that
morning's swap, on Jason's own call, rather than relaunched — it still
needs re-enabling by hand before BGTools' desktop features work again.

**The real library was set aside 2026-09-24** (Jason's own call, mid this
session): `~/Pictures/ShowTools Library.noindex` is now
`~/Pictures/ShowTools Library (2026-09-24).noindex`, untouched. The next
plain launch of the real app creates a fresh, empty library at the
default path.

## What's next

**Items 13, 14 and 30 are done** (2026-09-25, late): the Browser is a
drawer, any pane can switch sides, the frame strip is a drawer, and the
empty inspector's header sits at the top. No next task is set; the
feedback worklist's remaining items, the new asks and the parked list
below are what's open.

### New asks (Jason, 2026-09-25)

Not designed yet.

- **Pinch to change the grid's tile size** — in the Library grid (and the
  library panel's), the same as the size slider. Pinch already zooms the
  timeline and the viewer's work zoom (`spec/conventions.md` §1).
- **A drawer at the top of the grids with a viewer of the selected
  image(s)** — a PaneKit drawer over the grid, so it closes to its
  handle, and can switch sides like every other pane.

### Parked for later (Jason, 2026-09-25)

Not pressing; each wants a discussion or a plan before any code.

- **Plan the ReorderKit lift.** Drag-to-reorder into its own package,
  like PaneKit (a local package in the repo, its own tests and harness),
  for other apps. **No plan written yet** — only what would move:
  `ShowToolsCore/Reorder.swift` (+ `ReorderTests`) and
  `ShowToolsApp/ReorderDrag.swift`, with the grid's wiring in
  `LibraryGridView` (`startDrag`, `commitReorder`, `slot(at:)`, the
  fly-in and landing) as the part to turn into the package's API. App
  wording (`LibraryOrderNotice`) stays in ShowTools; the package only
  reports that a drag was refused where it was let go. Design, terms and
  dials: `spec/plan.md`, "Reordering".
- **A shared type for "explainer" notices.** Two now: `CustomOrderNotice`
  and `LibraryOrderNotice` (`CollectionAdd.swift`) — after-the-fact
  explanations, one OK button, "Don't show this again". Worth one type
  with the defaults, and a line in `spec/conventions.md` §6. Jason also
  wanted their text centred; macOS 27's `NSAlert` left-aligns by default
  and has no setting for it (centring would mean restyling after
  layout, or our own panel) — parked with this. Also Jason, seeing one:
  macOS 27's alert puts the app icon alone in the top-left with empty
  space beside it — "maybe room for the App name or something". Another
  reason to consider our own panel for this type.

**The 2026-09-24 cloud-planning work queue is done** — every item in it
(the audit batches, Groups inside collections, the range package, the
grid's keyboard, PaneKit steps 4–5, the popped-out Inspector and Timeline
panes) shipped 2026-09-24/25 and is already folded into "Where it stands"
above. Full dated story, including what each item's `swift test` run and
axtool check actually covered:
`spec/history/2026-09-25-work-queue-narrative.md`.

### The 2026-09-25 feedback worklist

Jason's own build feedback, `ShowTools Feedback — Worklist for Next CC
Session.md` (repo root), 37 items, worked through in batches grouped
by shared code. **26 done** (batches 1–8 below). Still open: 23–25 (BGTools), 26/27/29 (the value-changer panel
idea), item 2's other half, and 33–38, which are questions for Jason
(item 5 needed no code). Each fix checked
with axtool against a scratch library, not just compiled. Full dated
story — root causes, what each check actually covered, the commit for
each: `spec/history/2026-09-25-feedback-worklist-batches.md`.

| Batch | Done |
|---|---|
| 1 — PaneKit/window-layer | Items 1, 2, 9, 11 |
| 2 — library/collections | Items 3, 4, 6, 15, 16, 28, 32 (item 5 was a mislabel, no code needed) |
| 3 — frames row/transport | Items 7, 8, 18 (18 was already built) |
| 4 — BGTools | Items 10, 21, 22 |
| 5 — P2 polish | Items 30, 31 (31 was already built) |
| 6 — transport/icon, discussed 2026-09-25 | Item 19; item 12's icon half (its promotion idea is still open, above) |
| 7 — drawers, 2026-09-25 late | Items 13, 14; item 30 redone (the frame strip itself, not the timeline) |
| 8 — ratings, 2026-09-26 | Item 20 |

**Item 20 — built 2026-09-26** (Aperture's conventions, decided with
Jason by Q&A). A rating belongs to the **file**, so it lives where files
do — the Library grid, the library panel, Edit Show's browser, and the
inspector/Info panel's stars — never the timeline, the viewer, the frame
strip or the player. Keys (`Rating.Key`, `ShowToolsCore/Rating.swift`):
1–5 rate, 0 clears, **9 rejects**, − / = step (− stops at unrated and
leaves a reject alone; = lifts a reject to unrated; Jason: "−= might have
to be contextual, we'll get to that if it arises"). **U** shows/hides the
ratings (View ▸ Show Ratings (U), the `showRatings` default); the Library
grid's tiles now show stars at all, on a fixed-height line so rows stay
level. **Y** (Aperture's Viewer key) is Jason's for the **planned drawer
viewer over the grids** (new asks, below) — build it with that. A reject
is **−1 in the existing `rating` column** (no schema change); the rating
filter is Show All / Unrated or Better (the default, hides rejects, and
what every saved filter's 0 already meant) / ★…★★★★★ / Rejected Only.
**U is window-wide on purpose** (Jason's fix the same night: U jumped
the sidebar to "Untitled Collection" by type-select, since a tile click
leaves it the keyboard): `MainView`'s own `SingleKeys` takes U in every
mode, and the grid's rating digits run ahead of its sidebar check — see
`showtools-gotchas`. Re-checked with the sidebar holding the keyboard: U
both ways, no jump, a digit rates, the search box still types "u".
Checked with axtool on a scratch library: 3, 5 on two files at once, −,
9 (the file leaves the grid), Show All (its red ✕), U both ways (the
default flips), =, ⌘Z/Redo Rate, and a screenshot of level rows.

**Batch 6 — decided/built 2026-09-25** (this discussion):
- **Item 19** (transport greyed-out state) — **built**: the timeline
  pane's split now stays open in both edit modes (`MainView.isShowOpen`,
  was `isEditingShow`, gated on `mode == .show` too); Edit Slides shows
  `TimelinePanePlaceholder` (`EditShowTimelinePane.swift`), the same
  chrome dimmed and inert, instead of the pane closing and the window
  reflowing. Checked with axtool against the scratch library: the
  placeholder's "Switch to Edit Show to use the timeline" reads correctly
  in Edit Slides, and clicking back to Edit Show restores the real,
  interactive transport and storyline, screenshotted both ways. **Left,
  on purpose:** what a drop onto the greyed bar should do (item 33) — an
  Open Question Jason wants to answer once he has a working copy to play
  with, not before.
- **Item 12** (groups → a library item / catalog folder) — Jason's actual
  intent was already built 2026-09-24 (the Library pane's collapsible
  groups-and-shows list); the only missing piece, the icon convention
  (solid folder for a collection, outline for a group), is **built**
  (`collectionRow` now uses `folder.fill`, confirmed by screenshot). The
  bigger idea Jason raised alongside it — **promoting a group to its own
  collection** — is still a design question (`spec/plan.md`, "Groups
  inside collections," "Promotion"): what happens to the original group,
  and whether nested sub-groups come along.
- **Item 17 / 38** (drag-to-reorder) — **built and tried by Jason's
  hand, 2026-09-25**: an empty gap follows the pointer, one drop handler
  for the whole grid, a drop saves what's on screen, Undo Reorder works;
  several files drag as a tidy pile with a count badge, fly in on pickup
  and spring into place on drop; the grid scrolls near its edges, faster
  and with the pile shrinking as it nears them. Design, terms and dials:
  `spec/plan.md`, "Reordering". Story: `spec/history/2026-09-25-drag-reorder-rebuild.md`.
  A drag let go over the plain Library says why (`LibraryOrderNotice`);
  a drag nothing takes, or Escape, puts the files back (no message for
  Escape); the plain Library's sort strip names the sort in use.
  Left: the parked list under "What's next".
- **Item 13** (the Browser's own closed-drawer state, stacking with the
  Inspector's handle) — **step 1 built**: a fix it needed first.
  Dragging the Inspector shut (or open from its handle) changed the
  Browser's width, though a double-click didn't — measured on Jason's own
  copy, 236 → 545 pt. PaneKit's drag now moves the linked split by the
  space the side occupies, the same arithmetic as `setOpen`
  (`dragResize`, `PaneContainerView.swift`; two new `PaneControllerTests`
  that fail on the old code). Checked on a test copy: 236 through open,
  drag shut, drag open, drag shut. **Step 2 built:** the Browser is a
  drawer. Edit Show's columns are two splits nested from the right
  (`EditColumnsLayout`, new split ids `columns.inspector`/
  `columns.browser`), so the Browser closes to its own handle, the two
  handles stack at the right edge when both are closed, and every open,
  close or drag of either goes to the preview. View ▸ Show Browser (⌥⌘B).
  Checked on a test copy: double-click the divider and the handle, drag
  shut and open with the Inspector open (it stayed 320), the menu item and
  ⌥⌘B, and a screenshot of the two stacked handles. **Step 3 built —
  switching sides, for every pane** (a PaneKit feature, `spec/panekit.md`
  "What every pane can do"): drag a pane across main and, once less than
  its starting size is left, it trades places and mounts on the opposite
  edge. Checked on a test copy: the Browser to the left beside the
  Library pane (screenshot), closed there (handle on the left edge),
  dragged back by its handle; the Inspector across to the left
  (Inspector | preview | Browser, screenshot). **Left for Jason's hands:**
  the feel of all three steps, and the panes not tried at all — the
  Library pane, the timeline (it can switch to the top now) and Edit
  Slides' inspector. No menu command or animation yet.
- **Item 14** (the inspector's header at the top when empty) — **built**:
  bar + message were one short stack the pane centred. The inspector is
  now top-aligned (`SlideInspector.body`), and the empty message is an
  overlay centred on the whole pane (Jason: align the header, don't
  stretch the message to push it up — a first try did that). Screenshotted
  empty and with a slide selected on a test copy.
- **Item 30, done properly** (the frame strip as a drawer; batch 5 had
  read it as the timeline) — **built**: Edit Show's picture and frame
  strip are a PaneKit vertical split (`PreviewLayout`,
  `model.previewPanes`), replacing the hand-made 12 pt bar. Dragged below
  10 pt the strip closes to its edge handle; View ▸ Show Frame Strip
  (⌥⌘F) and the strip's Hide item now close it to the handle rather than
  removing it; it can switch to the top; it starts at the old bar's saved
  height (`frameStripHeight`, now unused after that first read). Checked
  on a test copy: drag closed, double-click the handle, drag to 214, the
  menu item and ⌥⌘F, to the top and back (screenshot). **For Jason's
  hands:** PaneKit's divider is a 1 pt line with a 7 pt grab band, where
  the old bar was a 12 pt band (he'd found the system split line too
  fiddly) — if it's fiddly again, that's a PaneKit-wide grab-width change.
  **Resizing live, fixed the same day:** Jason found the frames didn't
  follow a resize. Measured with screenshots mid-drag: the height followed,
  but every frame was blank until the drag stopped (frames are cached at
  one exact size and rendering waits 120 ms for a drag to settle — true of
  the old bar too). `FrameCache.nearest(to:)` now stands in the closest
  cached frame, stretched, until the real one renders.
- **Items 23–25** — queued as their own BGTools work list, to pick up
  once the ShowTools fixes above are done: `spec/bgtools.md`, "Next up —
  queued 2026-09-25, after the ShowTools fixes."
- **Items 26, 27, 29** (header-bar restyling, corner-radius override, app
  icons) — Jason's counter-proposal: a small **live value-changer
  panel** (corner radius, text size, control size, container-border
  visibility, …) as a reusable dev tool for tuning any app's look by
  trial and error, rather than one-off asks each needing a build. Not
  scoped yet: still needs a design pass (where its values live —
  UserDefaults keys the views already read, most likely — and which knobs
  it exposes first).
- Item 2's other half (a written window-layer hierarchy, and an audit of
  the built pop-outs against it) — still open, not started.
- **Simple things fast** — Jason confirmed 2026-09-25 all three answers
  (guided first run, Quick Show, the levels) are to be **built**, not
  chosen among. Its doc's own "Still open" list has shrunk to one real
  question (presets shared or separate between Quick Show and New Show…);
  status.md's older "Four questions" line was stale.
- **Windows of their own** — the built pop-outs (Slide Editor, the
  library panel, the Inspector, the Timeline pane) don't cover the whole
  original list: **the Library pane itself** (the sidebar, not the
  separate floating Library panel) and **the Browser** (Edit Show's file
  column) still can't detach. Answer 7 (double-click's meaning) is also
  still genuinely undecided — not superseded by the pop-out work.
- **Five Open Questions** in the feedback doc itself (greyed-transport
  drag target, glass/vibrancy in light mode, Show Similar's engine,
  large-library DB/indexing, the collections list column dropdown) —
  none buildable without Jason's call first.

### Also next

**Telling BGTools when a library moves** (B7 left it open). BGTools
reads the library at the path in its own settings, so if ShowTools'
library is moved or switched (Change Library), BGTools isn't told and
keeps looking at the old path. Jason isn't sure it's needed (2026-09-25)
— a question, not a task yet.

**Done, confirmed by Jason 2026-09-25:** the two listens (an exported
movie against the same show playing; a video slide's sound in the app),
a show built by hand from his own photos and music (v1 end-to-end), the
Mac-conventions audit (`spec/hig-audit.md`, G1 included), and right-click
menus area by area.

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

## Still needs Jason's hands

- **BGTools: naming screens, the map view, the window opening on your
  screen** (built 2026-09-25, `spec/bgtools.md` items 3–5): renaming a
  monitor or a Space, the Map | List switch, and the window landing on the
  calling monitor with its Space selected — all confirmed by their actual
  effect with axtool against a scratch settings file (live updates, no
  relaunch needed; `settings.json` read back correctly), but this Mac has
  one monitor, so the parts that are *about* more than one — the map
  actually laid out to scale, the window really following the pointer
  from screen to screen, ⌥-double-click actually moving it there — are
  reasoned through from the code, not seen. Worth a particular look with
  a second monitor plugged in.
- **Edit Show's inspector popping out** (built 2026-09-25, View ▸
  "Inspector in Its Own Window," `spec/panekit.md` "The order" step 4):
  the window itself, the main window closing up, the popped-out content
  following the main window's selection, and — after a same-session fix,
  `UndoMenuState` (`spec/panekit.md`, "Pane ⇄ panel") — undo, all
  confirmed with axtool against a scratch library: `Edit ▸ Undo` reads
  the real action name and a real ⌘Z/⇧⌘Z from the popped-out window
  undoes and redoes the edit, checked against the saved show's JSON.
  Never confirmed by a real click, drag or keypress from Jason's own
  hands.
- **The timeline pane, full width under the Library pane, and popping
  out** (built 2026-09-25, `spec/panekit.md` "The order" step 5): sits
  at x=0, under the Library pane, not starting at the detail column's
  left edge; the library and detail panes grow to fill the window's full
  height when Edit Slides or the plain Library view closes it; View ▸
  "Timeline in Its Own Window" still pops it out as an ordinary window,
  now at its own full width; bare-key shortcuts (Space, J/K/L, M, I, O,
  N, arrows), Undo/Redo, and the Show/View menu's Play/Pause, Set Range,
  Zoom, Loop and Go Back/Forward items all still work from the
  popped-out window after the move; a real slide Delete shows the
  slide-removal notice and removes just that slide (not "Delete Show?" —
  a real race between two separate Delete-key handlers, found and fixed
  the same day), with ⌘Z putting it back. All confirmed with axtool
  against a scratch library. Never confirmed by a real click, drag or
  keypress from Jason's own hands.
- **Rating keys in Edit Show's browser** (item 20, 2026-09-26): its
  rows show stars and ✕, but a synthetic click on a row left the keyboard
  on the sidebar, so neither the new rating keys nor the browser's
  **older E/W/Q** fired — both need the browser's list to have focus
  (`listFocused`). Pre-existing, not changed. Worth one real click and a
  keypress: if they fail by hand too, the browser needs the grid's
  window-level `SingleKeys` approach.
- **The grid's keyboard** (built 2026-09-25, audit batch 7): arrow keys,
  Return-renames, and Quick Look on ⌘Y or a double-click — all confirmed
  by their actual effect with axtool (selection counts, the rename sheet,
  a screenshot of the right file in Quick Look, the panel really closing
  on a second ⌘Y even while it was the key window), never by a real
  keypress or click. Worth a particular look: whether `columnCount`'s
  worked-out math ever drifts from `.adaptive`'s own at an odd window
  width or thumbnail size (only the default 250pt tile size, at the
  window's default width, was exercised).
- **Drops onto slides and Replace Image…** (built 2026-09-24, plan.md
  "Replace a slide's image"): Replace Image… from all four menus (only
  the storyline's was actually clicked through), the storyline's drag
  Replace-or-Insert (a real internal drag confirmed both, but never
  watched by eye), and the Edit Slides list's own per-row drop (G2's
  fix) — not exercised at all, a cross-window synthetic drag wasn't
  practical to set up. Worth a particular look: whether the storyline's
  replace-zone highlight (a box around the whole slide) and the list's
  fixed 12pt insert bands feel right, and whether the pixel bands scale
  sensibly if a row's height ever changes.
- **Timeline keys** (built 2026-09-24, `spec/conventions.md` §2): arrow-key
  navigation across all four rows and Go Back/Forward — checked with
  axtool against a scratch library's saved state (times, the enabled/
  disabled menu items, `Edit ▸ Undo` staying off), never by a real
  keypress or a real look at the storyline. Worth a particular look: the
  empty-row deselect gap noted above, and whether Go Back's scroll
  restoration (the nearest slide, not the exact offset) feels right.
- **The whole range package, W6–W10** (built 2026-09-24, `spec/plan.md`
  "The range and the ruler" and "Fill the range with images"): dragging
  an end, the lock (right-click of either end, the shaded span or the
  button), I/O/⌥X still landing while locked, the range button's
  plain-click/⌥⌘-click/⇧⌥⌘-click/right-click, the shaded span's own
  right-click menu, double-clicking a song section to set the range, and
  the Fill Range with Images dialog itself — all reasoned through and
  checked with axtool against a saved show's `editor` and `slides` tables
  and screenshots, never by a real drag or a real modifier-click (axtool's
  `click` can't hold two modifiers at once, so ⌥⌘ and ⇧⌥⌘ themselves are
  unverified beyond their Show-menu equivalents). Worth a particular look:
  whether a real drag feels right — the synthetic one moved further than
  its own on-screen distance implied, which may just be a tool artifact;
  whether scrubbing still feels normal across the whole ruler now that the
  range's shaded span carries its own copy of the seek gesture alongside
  `RulerView`'s; the Fill dialog's Library tab and a Displace fill (only
  Collection and Replace were clicked through); and the one-slide-inside-
  the-range edge case in `RangeFill` (a second use of the same file for
  what continues past the range's end) — reasoned through and tested, but
  not something the plan itself spelled out, so worth Jason's own read.
- **The viewer's menus, Show in Library, and the progress line fix**
  (built 2026-09-24, `spec/conventions.md` §3, item 4): every menu opens
  with the right items and every action was confirmed by its actual
  effect with axtool (Rotation Handles and Slide Progress toggle and
  report back, Show in Library opens the panel and selects the right
  file, Hide/Show Frame Strip round-trips, the progress line fills left
  to right), but none of it has been used by a real click yet. Worth a
  particular look: the known, accepted limitation that the image vs.
  pasteboard menu goes by which image was last clicked, not by the
  right-click's own location.
- **Edit Slides', the browser's and the inspector's menus** (built
  2026-09-24, `spec/conventions.md` §3, items 3/5/6): Copy/Paste and
  Copy/Paste Settings, the quick-settings submenus, Use Defaults for All
  Slides, the browser's Select in Timeline/Play from Here/Remove from
  Show, and both inspector section menus — all confirmed by their actual
  effect with axtool (slide counts and settings genuinely changed, not
  just the menu opening), never by a real click. Worth a particular
  look: Copy/Paste Settings are meant to swap in over Copy/Paste only
  while ⌥ is held, but are built as four always-visible items instead
  (SwiftUI's `.contextMenu` can't declare AppKit's alternate items) — if
  that reads as clutter in practice, the ⌥-swap is its own follow-up.
- **The library panel** (built 2026-09-24, `spec/panekit.md`, "Step 4,
  second piece"): opens and shows the whole library correctly, checked
  with axtool against a scratch library, but a real drag from it (its own
  reason for existing — filling a new collection with the panel floating
  over it) hasn't been tried by hand.
- **The grid's list view at the size slider's minimum, and the panel's
  slider now independent of the main window's** (Jason, 2026-09-24,
  `spec/windows.md` answer 6): checked with axtool — dragging the slider
  to its floor and back switches cleanly between a single-column list
  (small icon, filename, full-width selection highlight) and the tile
  grid, selection carries across the switch; the library panel's slider
  and the main window's grid now keep their own sizes (`gridTileSize` vs
  `gridTileSize.panel`), checked with both windows open at once, one in
  list view and the other mid-size — but never watched by a real drag of
  the actual slider control.
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
- **The menus batch 5 built 2026-09-24**: the Show and View menu items,
  Get Info from a slide selection, Show ▸ Play starting at the
  selection, and Help ▸ Keyboard Shortcuts — all reasoned through and
  compiled clean, but a menu can only really be checked by opening it.
  Worth a particular look: the toolbar's Inspector button and ⌘1/⌘2 lost
  or gained their shortcuts moving to the View menu, so it's worth
  confirming nothing doubled up or went silent.
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

## Right-click, 2026-09-26

Jason found right-click "not working" in the Library pane, the inspector
and the browser. Measured with a click logger on a scratch copy (his two-
finger taps arrive as right-clicks): the rows' menus work; what failed
was **places with no menu designed** (the browser's header, where his
taps landed; the inspector bar's empty stretch, now fixed) and **list
empty space**, where SwiftUI throws. Every such place now shows a greyed
**"No menu yet — place › area"** note (`spec/conventions.md` §3), so the
gaps are visible and listable (search `noMenuYet`, `ListEmptySpace`).
**Not covered yet:** the timeline, the transport, the filter bar and sort
strip, the defaults bar. Also found: deselecting in the browser left the
inspector on the old slide (fixed, both directions); in the timeline,
neither Escape nor a click on empty row space deselects a slide (only
⌘-click does) — `spec/conventions.md` §2 says Escape should, not built.

## Known issues

- **Edit ▸ Undo was disabled once after a rating key**, on one test copy
  (2026-09-26), though ⌘Z had nothing to undo either; four later tries,
  including the same order of actions on a fresh launch, all showed
  "Undo Rate" enabled and undid correctly, with a probe confirming the
  step was on the key window's own undo manager. Not reproduced, not
  explained — suspect `UndoMenuState`'s tracking of the key window
  rather than the rating code, but that's unproven.

- **`LibraryLocation.isInICloud` loops forever on a path containing
  `..`** (`ShowToolsCore/Library.swift:50`): `deleteLastPathComponent` on
  `..` never shortens the path. Hit with a test launch path
  `…/Library.sqlite/..`: the app hung at 100% CPU before opening a window,
  and needed `kill -9` (and its launch note cleared). Not fixed.
- **Undo registered outside an event stays invisible to Edit ▸ Undo
  until the next event** (AppKit's automatic group stays open). Fixed for
  drag-to-reorder by an explicit undo group; other paths that register
  undo from a `Task` or after an `await` haven't been checked.
- **Right-click on a list's empty space — fixed 2026-09-26.** The
  logged "Row index -1" exception (2026-09-25, and again 09-26) was a
  right-click below a SwiftUI list's last row: SwiftUI throws there and
  shows nothing, in the Library pane and the browser alike.
  `ListEmptySpace` now answers those clicks with a "No menu yet" note
  (`showtools-gotchas`). Reproduced, fixed and re-checked on a scratch
  copy: no exception, the note shows, rows keep their own menus.
- **The layout-loop crash — fixed 2026-09-23, and its 2026-09-24
  recurrence also fixed.** `NSGenericException` from AppKit's layout-loop
  guard; root cause was SwiftUI's `.inspector()` modifier, fixed by
  porting Edit Slides' inspector onto `ColumnsSplitView`
  (`spec/edit-slides-inspector-port.md`). Recurred once more from a
  `SingleKeys` monitor on the sidebar `List`, fixed by moving it to the
  `NavigationSplitView`. **Lesson kept live:** `.background(SingleKeys)`
  is safe on a plain SwiftUI container, not on a `List` or anything else
  AppKit backs with its own constraint-based layout — check before adding
  one to Edit Slides' or the storyline's own Lists. Full story:
  `spec/history/2026-09-23-crash-hunt.md`,
  `spec/history/2026-09-23-crash-hunt-session2.md`,
  `spec/history/2026-09-23-crash-hunt-session3.md`.
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
swift test                                  # 306 core + 13 BGTools tests
./make-app.sh                               # → build/ShowTools.app
tools/make-test-library.sh <scratch>/STTest # scratch library + generated media
open -n --env SHOWTOOLS_LIBRARY=<scratch>/STTest/TestLib.noindex build/ShowTools.app
```

Before launching any test copy, read the `showtools-testing` skill: a test
copy shares Jason's preferences domain, and a crashed one shuts his real
app out.
