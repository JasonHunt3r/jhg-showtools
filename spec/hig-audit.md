# Expected-behaviour audit — menus, context menus, keyboard and selection

**Status:** Audited 2026-09-24 against `43b1111`. **Fixed:** G1, in
code only: written in a cloud session, **not yet built or checked**.
**Left:** everything else below. The fix batches are at the end, in the
order proposed.

## What this is

*The rules these findings build toward are in `spec/conventions.md`.*

A pass over the app's code against what a Mac user expects: Apple's Human
Interface Guidelines (menus, context menus, keyboard, selection) and the
habits Finder, Photos and Final Cut Pro have taught. The earlier audit
(`spec/history/2026-09-21-audit.md`) was about correctness. This one is
about **conventions that were never built in**.

It's a **code audit, done in a cloud session**. Nothing was run, clicked or
measured. Each finding says what the code does and what a user would
expect, with the file and line. Anything marked *(check)* is inferred from
code and should be confirmed by hand before it's fixed.

Severity: **Med** = a convention users reach for without thinking, whose
absence reads as broken. **Low** = discoverability, consistency, polish.

"Stacks" is read here as Group Similar's groups in the Library grid, the
only stack-like thing the grid has.

## Where it stands

| Area | Works today | Missing |
|---|---|---|
| Edit menu | Undo/Redo (window undo manager); Delete, where `onDeleteCommand` is wired | Select All outside Lists, Duplicate, Cut/Copy/Paste of slides or files |
| Library grid | Click, ⌘-click, ⇧-click; Delete / ⌘Delete; ⌘A; a full context menu | Arrow keys, ⇧-arrows, rubber-band selection, Space (Quick Look), Return, double-click |
| Edit Slides list | Everything a `List` gives: arrows, ⇧-arrows, ⌘A, Delete, drag to reorder | Duplicate on ⌘D, a fuller context menu |
| Storyline | Click, ⌘-click, ⇧-click; J/K/L, Space, I/O, M, N, ⇧Z; Remove on a lane image/transition/marker's context menu | Arrow keys between slides, ⌘A, Escape for slides; the fuller context menus (Duplicate, style submenus, Show/Hide Line) |
| Library pane | Right-click Rename…, Delete…; the Delete key and ⌘Delete; undo for Delete Show and Rename Collection | Return or click-to-rename |
| Menu bar | File, View, Show | Edit Show's commands (all hidden), the inspector toggle, a real Help menu |

## A. The Edit menu

The app never touches the Edit menu (`ShowToolsApp.swift` has no
`CommandGroup` for `.pasteboard`, `.undoRedo` or `.textEditing`), so it
holds only what SwiftUI and AppKit add by themselves. That works inside
text fields and `List`s, and nowhere else.

- **A1 (Med) — Select All (⌘A) does nothing in the Library grid or the
  storyline.** Neither is a `List`, so nothing answers `selectAll:`. In
  Finder, Photos and Final Cut, ⌘A selects every file or clip in view.
  **Fixed in the Library grid, 2026-09-24** (`MainView.swift`): ⌘A joins
  Delete and ⌘Delete in the grid's `SingleKeys` monitor, selecting every
  item in `visible` (the searched, filtered, sorted set — the same scope
  Delete already works over). It stays disabled while a text field or the
  sidebar `List` has the keyboard, the same guard Delete already used.
  Checked with a real ⌘A keystroke (not just axtool synthetic events):
  selects all 11 tiles in a scratch library, and still does ordinary
  text select-all in the Search field. The storyline is still open — B1's
  fix direction (a focused scene value + Edit-menu item) turned out to be
  the more invasive path; `SingleKeys` alone was cheaper and matches how
  Delete already handles this exact grid-focus problem.
- **A2 (Med) — No Duplicate (⌘D).** **Fixed 2026-09-24 (batch 5), for
  slides.** Edit ▸ Duplicate (⌘D) calls `SlideActions.duplicate` through
  a new focused value (`requestDuplicateSlides`, `activeSlideSelection`)
  published by `ShowView`, so it works the same in both modes. **Not
  done: a selected lane image** — no Duplicate action exists for one
  anywhere in the app yet (not even in its context menu), so this would
  be new logic, not just a new way to call an old one; left for the
  right-click conversation, which is where a lane image's other missing
  actions (Show in Finder, Show in Library) live too. ~~Slides can be
  duplicated only from a context menu (`ShowView.swift:164`,
  `StorylineView.swift:621`). Finder and Final Cut both put Duplicate on
  ⌘D in the menu bar.~~
- **A3 (Low, but a larger job) — No Cut, Copy or Paste of slides or files.**
  Expected:
  - ⌘C then ⌘V copies slides, with their settings, within a show or into
    another one. Final Cut does this with clips.
  - ⌘C on Library tiles puts file URLs on the pasteboard, so they paste
    into Finder, Mail or Messages, as Photos allows.

  This needs a pasteboard type for slides, and a decision about pasting
  into a show whose collection doesn't hold the file (the "add to
  collection?" question, as a drop asks). Worth doing after everything
  else here.

## B. Library grid: keyboard and selection

- **B1 (Med) — The grid doesn't reliably take the keyboard.** Its own
  comment says so (`MainView.swift:552`): "a click on a tile never gave
  the grid the keyboard". Delete and ⌘Delete were routed round it through
  `SingleKeys`. Arrow keys, ⌘A, Space and Return would all hit the same
  wall, so this comes first.
  *Fix direction:* either keep going with `SingleKeys` (a key monitor,
  already proven in this window), or put the grid on an AppKit view that
  can be first responder. The monitor is the smaller change. It must still
  let keys through to Search and to a List (the Library pane) that has the
  keyboard, as the Delete handler already does.
- **B2 (Med) — Arrow keys don't move the selection.** Finder and Photos:
  ←/→ move to the previous or next tile, ↑/↓ move a row, ⇧ with an arrow
  extends the selection from the anchor, and the grid scrolls to keep the
  selection in view. The grid's column count comes from its width and
  `tileSize`, so ↑/↓ needs that number. `.adaptive` columns don't expose
  it, so it has to be worked out the same way, or the grid changed to
  fixed columns.
- **B3 (Med) — ⇧-click only ever adds.** **Fixed 2026-09-24** (batch 4):
  `MainView.swift`'s `click(_:)` now calls `GridSelection.shiftClick`,
  which replaces the previous ⇧-range from the anchor rather than
  unioning with it — the click-5-⇧-click-10-⇧-click-7 example is one of
  `GridSelectionTests`' worked examples. `swift test` is clean; a real
  ⇧-click in the grid still wants Jason's hands. ~~`MainView.swift:793`
  does `selection.formUnion(range)`. In Finder, ⇧-click *replaces* the
  last ⇧-range with the new one, from the same anchor. Click 5, ⇧-click
  10, ⇧-click 7: Finder has 5–7 selected, this grid has 5–10.~~
- **B4 (Low) — No rubber-band selection.** Dragging on the empty space
  between tiles selects nothing (in Finder and Photos it draws a
  selection rectangle, and ⌘ or ⇧ adds to what's selected). The
  background tap only clears the selection (`MainView.swift:679`).
- **B5 (Med) — No Quick Look.** Finder, Photos and every file
  browser use Space for Quick Look. **Settled (Jason, 2026-09-24): not
  Space here.** In ShowTools, Space is play/pause pretty much always.
  Quick Look is ⌘Y (Finder's other key for it) and double-clicking a
  tile (`spec/conventions.md` §1–2). `QLPreviewPanel` isn't used anywhere
  in the app. It could step through the selection with ←/→ as Finder's
  does.
- **B6 (Low) — Double-click and Return do nothing on a tile.** In Photos,
  double-click opens the picture large; in Finder, Return renames.
  *Decision for Jason:* double-click could open Quick Look (B5), or Get
  Info. Return → Rename… is the Finder convention.
- **B7 (Low) — A Group Similar group can't be selected as a whole.** The
  only action on a group is Keep One…. Selecting a group by clicking its
  header, or a context menu on the header (Select Group, New Show from
  Group, Add to Collection), would treat the groups as the stacks they
  look like.

## C. Context menus

HIG: a context menu holds the most-used commands for the thing under the
pointer. The app has good ones in the Library grid and the Collection
Browser. Elsewhere they're thin, or missing altogether:

- **C1 (Med) — Lane images have no context menu.** **The obvious part
  fixed 2026-09-24:** right-clicking a clip itself (not just the row) now
  offers Remove Image, the same `mutate("Remove Image")` Delete already
  uses. Still missing: Duplicate, Show in Finder, Open Inspector — the
  fuller menu waits for the right-click conversation.
- **C2 (Med) — Transitions have no context menu.** **The obvious part
  fixed 2026-09-24:** right-clicking a transition now offers Remove
  Transition (sets it to `.cut`, the same as Delete). Still missing: its
  style as a submenu, Use Show Default.
- **C3 (Low) — Markers have no context menu.** **The obvious part fixed
  2026-09-24:** right-clicking a marker now offers Remove Marker, the
  same `removeMarkers` Delete already calls. Still missing: Show or Hide
  Line.
  **C1–C3 all reuse the exact mutate call their Delete-key handler
  already uses** (`EditShowView.swift`), so the new code has no new
  logic to get wrong. Not confirmed by a real click, though: the
  storyline's transitions and markers are drawn on a custom canvas whose
  accessibility coordinates didn't line up with real screen points for
  axtool (`StorylineView.swift` reported a transition at x≈2232 in a
  1372-wide window) — `swift build`/`swift test` are clean, but these
  three specifically want Jason's own right-click.
- **C4 (Low) — A storyline slide's menu is Duplicate and Remove only**
  (`StorylineView.swift:619`). The same slide's menu in Edit Slides also
  has Play from Here (`ShowView.swift:167`). Expected in both: Play from
  Here, Show in Finder, Open Inspector.
- **C5 (Low) — Songs:** Detect Beats… and Remove Song
  (`MusicRow.swift:125`). Add Show in Finder.
- **C6 (Low) — The Library pane.** The Library row has no menu at all (Import…,
  New Collection would fit). Show rows lack Duplicate Show, Export Show…
  and Export Movie…, which are otherwise only in the File menu.
  **Settled 2026-09-24** (`spec/conventions.md` §3): the Library row gets
  Import…, New Collection, Open Library Panel and Show in Finder; a show
  gets Play on Desktop, Duplicate Show and an Export ▸ submenu (which
  the File menu uses too); a collection gets Play, greyed out until
  playing without a show is built. Duplicate Show and Play on Desktop
  need new code; the rest are menu items.
- **C7 (Low) — One action, two names.** Deleting a file from the library
  is "Move to Trash…" in the grid (`MainView.swift:751`) and "Delete from
  Library…" in the Collection Browser. Pick one: "Move to Trash…" says
  what happens.
- **C8 (Low) — Shortcut letters typed into titles.** The Collection
  Browser's menu reads "Append to Show  (E)". A shortcut set on the
  button with `.keyboardShortcut` would show at the right edge, as menus
  show every other shortcut. *(check)* whether SwiftUI context menus draw
  a bare-letter key equivalent without also turning it into a window-wide
  shortcut that eats typing. If they don't, leave the titles as they are.

## D. The Library pane

- **D1 (Med) — Delete does nothing on a selected show or collection.**
  **Fixed 2026-09-24.** The List's own `onDeleteCommand` is there for when
  it genuinely has the keyboard, but a click on a row leaves the window
  itself as first responder (measured, same problem B1 found in the
  grid) — so a `SingleKeys` fallback on the whole `NavigationSplitView`
  (not the List: see the crash below) handles Delete and ⌘Delete the rest
  of the time. Delete asks first; ⌘Delete skips the question, following
  the settled convention (plan, 2b).
  **A crash found and fixed along the way:** a first attempt put the
  `SingleKeys` monitor in `.background()` directly on the sidebar `List`
  (a real `NSTableView`, unlike the grid's plain `ScrollView`). Undoing a
  show deletion hit AppKit's layout-loop guard and crashed
  (`EXC_BREAKPOINT`, `~/Library/Logs/DiagnosticReports/ShowTools-2026-09-24-034845.ips`,
  thousands of repeated `CellHostingView`/`NavigationPaneModifier` layout
  frames) — the same class of bug as the `.inspector()` crash fixed
  2026-09-23, in a new place. Moving the monitor to the split view as a
  whole fixed it; the exact repro (select a show, ⌘Delete, ⌘Z) no longer
  crashes.
  Checked with real clicks and keystrokes, cross-checked against the
  library's own database, not just the accessibility tree (which was
  seen to lag one step behind after a delete — a known staleness, not a
  second bug): Delete asks, Delete Show removes the row, ⌘Z restores it
  with its old id.
- **D2 (Med) — Delete Show can't be undone.** **Fixed 2026-09-24**, with
  D1. `Library.snapshotShow`/`restoreShow` (mirroring
  `snapshotCollection`/`restoreCollection`) capture the show, its slides
  and their ids before deleting; `AppModel.deleteShow(_:undo:)` registers
  the restore as an undo step, redo as a fresh delete. Two new Core tests
  (`testADeletedShowComesBackWithItsIdAndSlides`,
  `testARestoredShowLeavesOutSlidesOfFilesDeletedSince`).
- **D3 (Low) — Rename Collection can't be undone.** **Fixed 2026-09-24**:
  `AppModel.renameCollection(_:to:undo:)` registers the old name as the
  undo step, the same shape as `renameShow`. Checked with a real rename
  and ⌘Z.
- **D4 (Low) — Renaming is an alert, not in place.** Finder and Photos:
  select a row and press Return, or click the name of a row that's
  already selected, and it becomes editable where it is. Here Rename…
  opens an alert with a text field (`MainView.swift:122`).

## E. The storyline (Edit Show)

- **E1 (Med) — ⇧-click extends from the first selected slide, not from
  the last click, and only ever adds.** **Fixed 2026-09-24** (batch 4):
  `StorylineView` now keeps its own `anchor`/`selectionBase` state (it had
  none before — the old code derived an "anchor" fresh each time from
  "the first selected slide") and calls the same `GridSelection` used in
  the grid. The click-2-⌘-click-8-⇧-click-10 example is one of
  `GridSelectionTests`' worked examples. `swift test` is clean; a real
  ⇧-click in the storyline still wants Jason's hands. ~~(`StorylineView.
  swift:650`). Click slide 2, ⌘-click 8, ⇧-click 10: Finder and Final Cut
  would add 8–10; here it selects 2–10. It's the same fix as B3, with an
  anchor that remembers the last plain click or ⌘-click.~~
- **E2 (Med) — No keyboard movement between slides.** The player already
  uses ←/→ for the previous or next slide, and Home/End
  (`PlayerWindow.swift:104`), but the editor doesn't. Final Cut uses ↑/↓
  for the previous or next edit, and ←/→ for a frame.
  *Decision for Jason:* in the storyline, either
  - ↑/↓ select and seek to the previous or next slide, and ←/→ nudge the
    playhead; or
  - ←/→ go by slide, as the player does.

  Also Home/End, and ⌘A (A1).
- **E3 (Low) — Escape doesn't clear a slide or transition selection.** It
  clears lane images, songs and markers only (`StorylineView.swift:349`).
- **E4 (Low) — Lane images and audio clips select one at a time.** ⌘-click
  and ⇧-click don't add, so several can't be deleted or moved together.
  **Settled: wanted** (Jason, 2026-09-24): ⌘-click adds to and removes
  from the selection there too.

## F. The menu bar

- **F1 (Med) — Edit Show's commands are in no menu.** **Fixed
  2026-09-24 (batch 5), following the proposal below exactly.** The Show
  menu: Play/Pause, Add Marker, Set Range In, Set Range Out (bare keys,
  named in the title, e.g. "Add Marker  (M)" — never `.keyboardShortcut`,
  per the *(check)* below), Clear Range (⌥X) and Loop Playback (⌘L, a
  `Toggle` showing the checkmark, both real shortcuts now — the *(check)*
  confirmed a menu item can carry the same modifier-bearing shortcut a
  hidden `Button("")` used to). The View menu: Zoom In/Out (⌘=/⌘−, now
  plain `@AppStorage` reads — `storylineZoom` is one global default, not
  per-window, so no focused value was even needed), Zoom to Fit (⇧Z, a
  focused value — needs the storyline's own geometry) and Snapping
  (a `Toggle`, `N` named in the title). All published by a single
  `editShowCommands` focused value (`EditShowView`'s `shortcuts()`),
  absent — so every one of these disables itself — whenever Edit Slides,
  not Edit Show, has the window. The hidden ⌘=/⌘−/⌘L buttons are gone
  from `EditShowView`; the bare-key ones stay on `SingleKeys`, unchanged.
  ~~⌘= and ⌘− (zoom), ⌘L (loop), J/K/L, Space, I/O, ⌥X, M, N, ⇧Z and the
  browser's E/W/Q are hidden buttons or key monitors
  (`EditShowView.swift:170`).~~
- **F2 (Low) — The inspector toggle (⌥⌘I) is only a toolbar button.**
  **Fixed 2026-09-24 (batch 5).** Both `inspectorShown` and `editMode`
  are single global `@AppStorage` keys already (one window's inspector
  or mode is every window's), so View ▸ Show Inspector (⌥⌘I, a `Toggle`)
  and View ▸ Edit Slides/Edit Show (⌘1/⌘2) needed no focused value at
  all — just reading the same keys `ShowView` already does. The toolbar's
  own Inspector button lost its `.keyboardShortcut` (kept only on the
  menu's `Toggle` now, so there's one shortcut, not two registered for
  the same keys).
- **F3 (Low) — The Help menu is SwiftUI's default.** **Fixed 2026-09-24
  (batch 5), the "make it Keyboard Shortcuts" option.**
  `CommandGroup(replacing: .help)` opens a new `KeyboardShortcutsView`
  window listing the bare-key commands (playback, the timeline, the
  browser, selecting) that have nowhere else to show themselves —
  everything with a real modifier already shows its shortcut in its own
  menu, so it isn't repeated there.
- **F4 (Low) — Get Info (⌘I) works only in the Library grid.** **Fixed
  2026-09-24 (batch 5), for a slide's file.** The File menu's one
  Get Info button now checks the show's slide selection
  (`activeSlideSelection`/`requestSlideGetInfo`, `ShowView`) before
  falling back to the Library grid's own — opening the same `InfoPanel`
  either way, on the selected slides' files.

## G. Edit Slides vs Edit Show

The two modes are two views of one show, built for different jobs:
Edit Slides is a list, for order and per-slide settings; Edit Show is a
timeline, for time, layers and audio. They share one selection (`ShowView`
holds it), and **they don't have to offer the same tools**. Edit Slides
has no viewer and no rows, and shouldn't grow them.

**The rule is narrower, and a leaning, not a law:** where both modes
offer the same action on a slide, it should usually give the same
result, so a person who learned it in one mode isn't surprised in the
other. A mode may depart where a different behaviour is clearer there;
Jason decides those (`spec/conventions.md`, ground rule 1).

- **Should match** (the same action, in both):
  - selecting: click, ⌘-click, ⇧-click, ⌘A;
  - undo: every change is one step, in both;
  - what double-click on a slide does, once that's decided;
  - the slide's core context-menu items (Duplicate, Remove, Play from
    Here, Show in Finder, Show in Library);
  - Delete;
  - a drop: both have positions, so both insert where the drop lands.
- **May differ** (it follows the mode's job):
  - playback keys: Space and J/K/L play in the viewer, and Edit Slides
    has none;
  - timeline-only actions: trims, rolls, the lane, markers;
  - what the list shows per slide (length, transition, Pan and Zoom as
    text), where the timeline shows them as shapes.

Today they disagree on several of the "should match" items:

| | Edit Slides (list) | Edit Show (storyline) |
|---|---|---|
| Arrow keys, ⇧-arrows, ⌘A | Yes (a `List` gives them) | No (E2, A1) |
| ⇧-click | Finder's rule (a `List`) | Finder's rule too, fixed 2026-09-24 (E1) |
| Double-click a slide | **Toggles** the inspector (`ShowView.swift:171`) | **Opens** it, never closes it (`StorylineView.swift:662`) |
| Context menu | Duplicate, Remove, **Play from Here** | Duplicate, Remove (C4) |
| Space, J/K/L | Nothing | Play and shuttle |
| Dropping files | **Appended to the end**, wherever they land (`ShowView.swift:181`) | Inserted where they land, songs into the music row (`StorylineView.swift:912`) |
| Undo a drop | **Can't** (G1) | Yes |
| Delete | Removes the selected slides | The lane's selection first, then slides |

- **G1 (Med, a bug) — Adding slides can't be undone, except in Edit Show.**
  `AppModel.append` (`AppModel.swift`) takes an optional undo manager, and
  none of its callers pass one:
  - a drop onto the Edit Slides list (`ShowView.swift:181`)
  - a drop onto a show in the Library pane (`MainView.swift:213`)
  - the grid's Add to Show menu (`MainView.swift:760`)

  So `update` registers no undo step, and ⌘Z undoes whatever came before.
  The storyline's drop and the browser's Append go through `mutate`, and
  undo properly. This breaks the rule that every show edit goes through a
  `ShowMutator` with an undo name. *Fix:* pass the window's undo manager at
  all three calls.
  **Fixed 2026-09-24, unbuilt.** All three calls pass it, and `append`'s
  `undo` no longer defaults to nil, so a new caller can't leave it out.
  Undo takes the slides back out. Files the add put into the show's
  collection stay in it (adding to a collection has no undo anywhere,
  which is a separate matter). *Check:* drop two files onto the Edit Slides
  list, then Edit ▸ Undo reads "Undo Add Slides" and ⌘Z removes them. Do
  the same with a drop onto a show in the Library pane and with Add to Show.
- **G2 (Med) — A drop onto the Edit Slides list ignores where it lands.**
  Dropping between slides 3 and 4 still appends to the end, while the same
  drop onto the storyline inserts there. A `List` shows an insertion line
  for `.onInsert`, which gives the index. Songs dropped here are silently
  dropped (`append` keeps only pictures), where the storyline puts them in
  the music row. Here they could be refused, so the drop isn't accepted.
- **G3 (Low) — Double-click opens the inspector in one mode and toggles it
  in the other.** Pick one. Toggling matches Edit Slides and the browser
  (`CollectionBrowser.swift:237`).
- **G4 (Low) — Space does nothing in Edit Slides.** There's no preview
  there, so Space can't play in place. Space → Play from the selected
  slide (in a window) would match Edit Show's key. Otherwise it's simply
  one more thing that behaves differently between the modes.
- **G5 (Med) — Show ▸ Play doesn't start where the toolbar's Play does.**
  **Fixed 2026-09-24 (batch 5).** `play(fullScreen:)` now works out
  `startAt` the same way `ShowView.firstSelectedIndex` does, from the
  new `activeSlideSelection` focused value — the same one A2/F4 needed,
  so this came for free once it existed. ~~The toolbar's Play and Play
  Full Screen start at the first selected slide (`ShowView.swift:62`).
  Their help text names ⌥⇧⌘P and ⌥⌘P, but those menu items call
  `Player.open` with no `startAt` (`ShowToolsApp.swift`,
  `play(fullScreen:)`), so the same shortcut starts from the top.~~

- **G6 (Med) — Show defaults can only be changed in Edit Slides.** The
  defaults bar (`ShowView.swift:144`) is Edit Slides' alone, so in Edit
  Show there's no way to reach the default length, transition, fit or
  background without switching mode. Found while writing
  `spec/anatomy.md`. *Decision for Jason:* where they go in Edit Show.
  The options are the inspector with nothing selected (it shows "No
  slide selected" today) or a popover from the transport.
- **G7 (Low) — The timeline's row order looks like layer order, and
  isn't.** Dragging the images row under the slides row moves it on
  screen only. Lane images are still drawn over the slides
  (`spec/anatomy.md` §4). Either say so where the rows are reordered, or
  decide that row order *is* layer order before a show can have two rows
  of one kind.

## H. Making new things (Jason, 2026-09-24)

- **H1 (Med) — New Collection and New Show skip naming.**
  **New Collection fixed, 2026-09-24.** Every path that made one with no
  real name — the sidebar's + menu, File ▸ New Collection…, and the
  grid's "New Collection from N Items" / "New Collection…" — now asks
  first (an alert, `TextField` pre-filled with the next free "Untitled
  Collection" name) and creates only on Create; Cancel makes nothing.
  Wired through a new `requestNewCollection` focused scene value
  (`SlideInspector.swift`), published by `MainView` itself rather than
  the grid, so File ▸ New Collection… still works whatever the detail
  pane is showing — unlike Rename…/Get Info, which are genuinely
  grid-scoped. Checked with real clicks and keystrokes: Cancel creates
  nothing, Create with a typed name makes exactly that collection and
  selects it.
  **New Show is still open, on purpose:** made from a selection, it used
  fixed defaults with no dialog, so the lengths and the dissolve had to
  be fixed afterwards. Its naming step is the shared settings panel in
  `spec/simple-things-fast.md` (name, length, transition, Pan and Zoom,
  audio, presets) — a separate, larger piece of work, already tracked on
  its own. Building a throwaway name-only dialog for New Show now, ahead
  of that panel, wasn't worth it.
  - *Exception to settle with the first run:* a new library starts with
    one collection made for you (`spec/first-run-brief.md`, "My First
    Collection" with a Rename button). That one is made by the app, not
    by a click.
- **H2 (Med) — An empty collection or show has no way in on its face.**
  *Scope:* this is about empty **containers you're meant to fill** (the
  library, a collection, a show). Other empty places are different and
  don't all want a button:
  - *Empty because of a search or filter:* say so, and offer to clear the
    filter, not Import. The files exist; they're just hidden.
  - *Empty because nothing is selected* (the inspector, the Info panel):
    say what to select. The selection is the way forward, so no button.
  - *An empty row in the timeline* (images, audio): a hint to drop
    something there, as the images row has now. Dragging is the natural
    way in, and a button in a 30-point row would be clutter.
  - *Not empty at all but unused* (a disclosure closed, a drawer with
    nothing in it yet): nothing to say.
  **The second tier's buttons built 2026-09-24:**
  - an empty collection: **Import…** (into this collection, already
    correct since the panel starts on the collection the sidebar's in)
    and **Add from Library…** — a new `MultiItemPicker` sheet (same shape
    as `LibraryPicker`, "Place Image Here…", but multi-select with an Add
    button), showing every library file not already in the collection.
    Replaces the library panel this was meant to open once one exists.
  - an empty show (Edit Slides only — Edit Show's storyline wasn't in
    scope): **Add from Collection…**, the same `MultiItemPicker` scoped
    to the show's own collection's pictures, and **Import…**, a new
    `runImportIntoShowPanel` that imports then appends straight to the
    show (the existing `runImportPanel` imports into a *collection*, a
    different target).
  Checked with real clicks and keystrokes (one button click needed a
  retry to land — the same synthetic-click flakiness noted elsewhere,
  not a bug; `Return` on the picker's default-action Add button worked
  every time): an empty collection picks up two files from the library,
  an empty show picks up one from its collection, both without leaving
  the window.

  **Two tiers of wording (Jason, 2026-09-24),** the same shape as the
  guided first run (`spec/first-run-brief.md`):
  - **The first time** an empty place is seen: a welcome, a fuller
    lesson, and the button.
  - **Every time after:** a short reminder of what the place is for, and
    the button.

  The buttons are the same in both tiers, and they're H2. So H2 builds
  the second tier now, and the first run later adds the first tier on
  top, without changing H2. Most people see the empty Library once,
  unless they make a new library, so its welcome is the first run's job.
  See also `spec/windows.md`, "Filling a new collection".
- **H3 (Med) — File ▸ Import… can't choose audio files.** **Fixed
  2026-09-24**: `allowedContentTypes` gained `.audio`, and the panel's
  message reads "images, videos or audio".
- **H4 (Low) — The import failure says "song".** **Fixed 2026-09-24**:
  `Ingest.Failure.notMedia` now reads "not a readable image, video or
  audio file", the name settled 2026-09-24.

## I. Panes lost past the window's edge (Jason, 2026-09-24)

- **I1 (Med) — A pane dragged to the edge can vanish with nothing to grab
  back.** Jason dragged the Library pane's divider (the library and
  collections, on the left) to the window's edge, and the Library pane went
  past it and couldn't be recovered. It happened on the right side too,
  at one point. The Library pane is SwiftUI's `NavigationSplitView`, which
  collapses below its 180-point minimum and leaves no handle. *(Check:*
  whether a toolbar or View-menu sidebar toggle brings it back. The app
  doesn't add `SidebarCommands`, so the View menu may have no Show
  Sidebar item.) The inspector is the one pane that collapses by design, and
  its way back is an invisible strip (`ColumnsSplitView.revealByDragging`).
  Status's known issue, "pulling the inspector's divider far to the left
  breaks the layout", may be related.
  *Fix direction:* edge handles, visible on every edge a pane can close
  against (`spec/windows.md`, "Panes that close to an edge"). Until
  they're built, a pane shouldn't be able to go past the edge without
  one; View ▸ Restore Default Layout (⌥⌘0) is the way back today.

## Fix batches (proposed order)

Each batch is one commit and can be written in a cloud session, **unbuilt**:
Jason builds, runs `swift test` and does the hands-on check listed. They're
ordered from least to most risk.

1. **Undo** (G1, D2, D3). G1 is a real bug and a one-line change at each
   call. *Check:* drop files onto the Edit Slides list, then ⌘Z takes them
   out; the same for Add to Show; delete a show, then ⌘Z brings it back;
   ⌘Z a collection rename.
2. **Context menus, empty states, naming, and matching the two modes**
   (C1–C7, H1–H4, G3). These only add buttons that call actions that
   already exist, or change one line. *Check:* right-click each thing
   once; New Collection goes straight to its name; an empty collection
   and an empty show each offer their buttons; double-click a slide twice
   in each mode.
3. **Library pane Delete key** (D1). *Check:* Delete asks first, and ⌘Delete
   doesn't.
4. **Selection logic, moved into Core and unit-tested** (B3, E1, and the
   index arithmetic for B2/E2): a small `GridSelection` type (anchor,
   click, ⇧-click, ⌘-click, arrow step given a column count) with tests.
   The tests are written here and pass or fail on the Mac, which makes
   this the most checkable batch. *Check:* the tests, then ⇧-click in the
   grid and the storyline.
5. ~~**Menus**~~ (A2, F1–F4, G5) — done 2026-09-24. *Check:* each item is
   enabled at the right times, typing in Search still types, and
   Show ▸ Play starts at the selected slide. Full story at each of
   A2/F1–F4/G5's own entries above.
6. **The Edit Slides list's drop position** (G2). *Check:* drop between
   two slides, and they land there.
7. **The grid's keyboard** (B1, B2, A1, B5, B6). The riskiest batch: it
   depends on the focus problem that stopped the Delete key before.
   **⌘A in the grid is Jason's top priority** (2026-09-24: hand-clicking
   4,000 test images). It can go ahead of the batch on its own: an Edit ▸
   Select All menu item whose action selects every tile in view doesn't
   depend on the grid having the keyboard, since the menu item works from
   the menu bar either way.
   *Check:* by hand, with axtool if Jason isn't using the app.
8. **Later:** rubber-band selection (B4), group selection (B7), several
   lane images or songs at once (E4), Cut/Copy/Paste (A3), and inline
   rename (D4).

## Decisions for Jason

- **B6:** what double-clicking a tile does: Quick Look, Get Info, or
  nothing.
- **E2:** arrow keys in the storyline: ↑/↓ by slide as in Final Cut, or
  ←/→ by slide as in the player.
- **A3:** whether Copy/Paste of slides is wanted at all, and what pasting a
  file from outside the show's collection does.
- **G4:** what Space does in Edit Slides: play from the selected slide, or
  nothing.
- **G6:** where show defaults go in Edit Show.
- **G7:** whether the timeline's row order should become layer order.
