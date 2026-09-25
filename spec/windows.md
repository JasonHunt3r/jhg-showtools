# Windows of their own — the edit suite inside the edit suite

**Status:** Planned: a vision, not yet designed. Six of Jason's seven
answers are in (below). **Left:** what comes first, then a design with
Jason; much of it is settled by trying it.

**Superseded by PaneKit, 2026-09-24** (`spec/panekit.md`): this doc's own
"suggested approach" below — a standalone harness proving `ColumnsSplitView`
plus edge handles hold together before touching the app — is **done**,
generalized rather than ShowTools-specific, and merged into the app
(steps 1–3). Read `panekit.md` for what that harness became. Everywhere
below that says `ColumnsSplitView`, `NavigationSplitView` or "the custom
splits already work," read PaneKit: it's what those sections' outcome
was. PaneKit already does the pane-moving this doc calls for — pop out,
put back, remembered frames, the main window closing up. **The show
session is done too** (2026-09-24, "What stands in the way" below), and
so is the order question: Slide Editor, then the library panel, then one
detachable area (`spec/panekit.md`, "The order"). **The Slide Editor's
v1 and the library panel are both built** (`spec/panekit.md`, "Step 4,
first piece" and "second piece"); what's left of this doc is the
detachable area and the open questions under "Jason's answers" below.

Names follow `spec/anatomy.md`.

## The idea

The main window holds everything, and everything takes space in it. Many
of its areas should also work **in a window of their own**, and leave the
main window when they do:

- the collections list, popped out and dragged next to where files are
  being dropped from;
- the library as a list window, for the same reason;
- the timeline pane as a tool window of its own;
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
| **Library pane** (collections and shows) | Next to Finder or Photos, as a drop target |
| **Library** as a list | The same, and as a source to drag from while Edit Show fills the main window |
| **Browser** | Its files beside the timeline pane on a second screen |
| **Inspector** | Settings where they're wanted, and the columns get its width back |
| **Viewer** | Already done: the pop-out viewer (`Player.popOut`) shares the viewer's playback |
| **Timeline pane** | The rows full width, on their own screen: the **Timeline window** |

### 2. Editors for one thing

Opened *from* the thing, by double-click or a context menu. They aren't
in the View or Window menu, because each one is about a particular slide
or row, not a place in the app. There can be several, and they close
when done.

- **A row, opened up:** one row (say the audio row, or the images row) in
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

## The timeline pane

**The timeline pane** (Jason first called it the edit zone) is the unit
that holds the rows: the transport, the ruler and the rows under it.
Final Cut, Premiere and Resolve all call this the timeline. It's the
thing that could be a tool window of its own, the Timeline window. The
transport goes with it, since zoom, snapping and the range belong with
the rows wherever they are.

## Panes that close to an edge, inside one window (Jason, 2026-09-24)

The same flexibility, before any pane leaves the window: every pane can
close against the window's edge, and come back from it.

**The fail state it came from:**
- Jason dragged the **Library pane's** divider (the library and collections,
  on the left) to the window's edge. The Library pane disappeared past the
  edge, and there was nothing left to grab.
- It wasn't the only pane he lost that way. The right side went too, at
  one point. Whether that can still happen isn't known.
- *From the code:* the Library pane is SwiftUI's own `NavigationSplitView`,
  which collapses when dragged past its minimum (180 points) and puts
  nothing on the edge to pull it back. Edit Show's inspector, on the
  right, is the other pane that collapses. It leaves an invisible strip
  at the right edge that reveals it when dragged
  (`ColumnsSplitView.revealByDragging`), so there's no way to know it's
  there either.

**The idea: the bug becomes a feature.**
- **Closing to an edge is allowed, on purpose.** When a pane closes, an
  **edge handle** stays on that window edge: thin, but always visible and
  clickable. It's the same kind of grip as the bar over the frame strip
  (12 points, with a capsule), which replaced a system line that was too
  fiddly to grab.
- **Where things close to:** the Library pane to the left edge; the timeline
  pane to the bottom edge; the browser (the collection's files) and the
  inspector to the right edge.
- *The Library pane is the hard one:* it's SwiftUI's own split view, which
  offers no edge handle. Adding one means either an overlay that asks
  SwiftUI to show the Library pane again, or taking the Library pane onto
  `ColumnsSplitView`, the house pattern (`spec/how-we-design.md`,
  "Volunteered work follows the house pattern"). That's a harness
  question before it's a build. Then the window can be one big viewer, with every section a
  handle away.
- **Gestures** (`spec/conventions.md`):
  - drag a handle to open the pane to a width, or to resize it;
  - **double-click a handle to open or close its pane**;
  - a modified click reopens a closed pane too.
- **With the panels** (the rest of this file), that makes a single-window
  layout and a many-window layout, from the same panes.

### What it means to leave SwiftUI's split view (assessed 2026-09-24)

The main window's left pane (the library, collections and shows) is
SwiftUI's `NavigationSplitView` (`MainView.swift`). It's Apple's
ready-made two-column window. Two of Jason's ideas can't be done inside
it:
- **A timeline pane edge to edge.** `NavigationSplitView`'s left pane
  always runs the full height of the window, so nothing can sit under
  it. The timeline pane, which lives in the right-hand column today,
  can't reach the left edge while this container is in use.
- **An edge handle for the left pane.** It collapses below its minimum
  (180 points) and offers nowhere to attach a handle.

**What `NavigationSplitView` gives for free, and would have to be
rebuilt:**
- the translucent Mac sidebar look under the title bar;
- the toolbar's show/hide button for the left pane, and its animation;
- keyboard focus moving between the list and the content;
- its width being remembered.

**What leaving it gives:**
- full control of the layout: the timeline pane under everything, edge
  handles on every edge, any pane able to close;
- one mechanism for the whole window: `ColumnsSplitView`, the app's own
  hand-built split, which Edit Show's columns already use. It's the
  mechanism the crash fix moved Edit Slides onto
  (`spec/edit-slides-inspector-port.md`), and it has been reliable since.

**The cost and the risk:**
- It's a restructuring of the main window, not a tweak. Everything that
  hangs off `NavigationSplitView` today moves: the navigation title, the
  toolbar placement, the per-library `.id` reset of the detail.
- AppKit layout here has bitten before (CLAUDE.md: check it in a
  standalone harness or a layer-tree dump first).
- The translucent look can be kept with a visual-effect background, but
  that's hand work.

**Leaning: leave it (Jason, 2026-09-24).** Writing the replacement is
cheap for Claude, so losing the free parts costs little in code. The
cost that remains is **checking**, not writing: layout bugs that only
show when run (the inspector crash worked for days before it failed),
the small native behaviours (focus, VoiceOver, the toolbar button,
remembered widths), and the fact that only a Mac can run it. The
harness below is what keeps that cost small.

**And the other built-in split (Jason, 2026-09-24): don't use the
built-ins for panes at all.**
- What `NavigationSplitView` gives is **one divider** (the left pane's),
  plus the extras listed above. The full-width timeline pane removes that
  divider anyway, since it can't coexist with a full-height left pane.
- Edit Show's columns and timeline pane are split by `VSplitView`, the
  thin system line, which is exactly the kind of divider edge handles
  replace.
- The custom splits already work: Edit Show's three columns and Edit
  Slides' two, on `ColumnsSplitView`, since the crash fix.
- So: **every pane edge on the app's own split view, with handles.** The
  built-ins become the reference for what to recreate (focus, the
  toggle, the look, remembered sizes), not parts of the app.

**Built as a reusable library (Jason, 2026-09-24):** the pane system,
edge handles and the pane ⇄ panel pop-out go into **PaneKit**, our own
pane library, reusable in other Mac apps: `spec/panekit.md`.

**Suggested approach, done** (`spec/panekit.md`, steps 1–3): a standalone
harness first, answering "does it hold together" before the app was
touched — then the app's own main window and Edit Show's/Edit Slides'
columns moved onto it. The show session (below) doesn't
depend on this, so they can go in either order.

### The timeline pane's left edge: the drawers

The timeline pane is always edge to edge. Along its left side are the
rows' **drawers**: each row's settings, the rows' prefs.

- **A left handle sets where the timeline rows start.** Sliding it right
  exposes more of the drawers; sliding it left gives the rows more room.
- **The drawers are designed for any width.** Each has **icon-style
  buttons at its left-most edge**, so even a narrow strip of drawer is
  usable.
- **Opening a drawer fully** lays it over its row while it's in use. When
  you're done, it goes back to where it was.
- **⌘⌥-click on a row** opens that row's drawer (conventions).

**Two ways to build the left edge. Try the first, and fall back to the
second:**
1. **Try first: the row handles that exist.** Each row already has its
   own handle at its left end (`StorylineView.rowHandles`: drag to move
   the row, click for its drawer, ⌥-click for all of them). They may be
   all that's needed, with no new divider.
2. **If that doesn't work out:** one full-height divider for the whole
   pane (where the rows start), plus each row's own handle.

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
  is selected, which is how a detached browser or timeline pane would behave.
- **In-app drags between windows:** `ItemDrag` carries library ids, so a
  drag from a detached library or collection list into the timeline pane
  works as it does now within one window.

## What stands in the way (from the code, before any design)

- ~~**The show's editing state lives inside views.**~~ — **done
  2026-09-24** (`spec/panekit.md`, step 4's own prerequisite): the slide
  selection, the engine, the lane's transition/overlay/song/marker
  selections and the storyline's scroll offset are `ShowSession.swift`
  now, one object per open show, owned by `AppModel`
  (`AppModel.session(for:)`, `.closeShowSession()`) — not `@State` in
  `ShowView` or `EditShowView`. `ShowView` and `EditShowView` still read
  and write it through `Binding`s built from the session (`@Bindable var
  session = session`), so the child views below them (`PreviewStage`,
  `CollectionBrowser`, `StorylineView`, `SlideInspector`) needed no
  changes at all. The screen didn't change: verified against a real demo
  show (`tools/make-demo-show.sh`) — selection survives switching between
  Edit Slides and Edit Show, the engine's lifecycle is unchanged (made
  when Edit Show is entered, shut down when it or the whole show is
  left), and leaving the show and reopening it starts a fresh session,
  same as the old `@State` did. Still true and still ahead: zoom
  (`storylineZoom`/`snapping`) stays app-wide `@AppStorage`, not part of
  the session, since it never was per-show; the audit's menu work
  (`spec/hig-audit.md` batch 5) this was also meant to simplify hasn't
  been revisited yet.
- **Keys are per window.** `SingleKeys` (J/K/L, Space, I/O…) is a monitor
  on one window, and menus read focused values from the key window. A
  detached timeline pane needs its own, so Space still plays when it's the
  key window.
- **The columns assume their members.** `ColumnsSplitView` already hides
  the inspector. Taking the browser or the viewer out as well means it
  must lay out whichever columns remain.
- **Window APIs and the layout-loop crash.** The crash was SwiftUI's
  `.inspector()`. New windows should follow the Info panel's pattern (an
  AppKit window hosting SwiftUI) rather than new SwiftUI scene or
  inspector APIs, until a harness says otherwise (CLAUDE.md: check AppKit
  layout in a harness first).

## Jason's answers (2026-09-24)

1. **What comes first: settled 2026-09-24** — the Slide Editor, then the
   library panel, then one detachable area (probably the inspector), then
   the timeline pane last ("A possible order" below, which is now a plan,
   not a guess).
2. **Following the show depends on the window's job.**
   - Windows tied to playback follow the show's state: the timeline pane,
     the transport, the viewer. They show what's playing and where.
   - Windows that are a *source* don't follow playback. The library
     window doesn't jump to whatever image is on screen.
   - The two are joined on request instead: a context-menu item, **Show
     in Library**, on a slide, lane image or audio clip. It opens the
     library window and selects that file.
3. **Floating or ordinary also depends on the job.** Settled so far
   (later the same evening):

   | Window | Kind | Why |
   |---|---|---|
   | **Library** | panel (floats) | It floats over a new, empty collection so files can be dragged into a big target. This is the use that started the idea (see "Filling a new collection" below) |
   | **Inspector** | panel (floats) | Settings stay in reach over whatever is being worked on. It keeps its place over time |
   | **Timeline window** | ordinary window | It must be able to go *behind* the main viewer, especially once a show has extra rows |
   | **Slide Editor** | bold and in front, transient | Like a big popover: you work in it, and when you're done it goes away |

   The rest are found by trial and error.
4. **Launch restores everything:** which windows are open or detached,
   where they are, their sizes and states. The possible exception is the
   playhead.
5. **The main window closes up.** When an area leaves, its neighbours take
   the space. With the inspector out, the viewer widens and the browser
   slides over. With the browser out as well, the viewer takes that space
   too.
6. **The library list is a floating window, a panel** (confirmed: see 3).
   - On the Mac, a *panel* is a window that floats above the app's other
     windows (the Info panel is one). An ordinary window can go behind.
   - It opens from the **Library** item in the Library pane, which stays there.
   - Its size is free, above a minimum. Narrow, it's a list. Wider, the
     thumbnails grow until each is as wide as the window, a stacked list
     of images. That's the resizing the grid already does with its size
     slider, driven by the window's width. So it's probably the grid
     itself, not a second view.
7. **Double-click: not decided, and to be settled by real testing.**
   - Jason's original idea: double-clicking a collection opens its
     disclosure if it's closed.
   - The app has grown since, so double-click may be better as one
     unified meaning across every element.
   - ⌥-click is the likely partner. Either double-click opens the
     disclosure and ⌥-click opens the Slide Editor, or the other way
     round.
   - Worth knowing when this is tried: ⌥-click on a row handle already
     opens or closes every drawer at once.

## Filling a new collection: the problem the library panel solves

Today, making a collection and filling it goes like this:

1. File ▸ New Collection makes "Untitled Collection" and selects it.
   There's no naming step (see `spec/hig-audit.md` §H).
2. The collection is empty. Its message says to drag photos in, or to
   use Add to Collection from the Library, but there's no button.
3. So you either hunt for the small Import button in the toolbar, or
   select the Library, pick files, and drag them onto the collection's
   small row in the Library pane.

With the library panel floating over the empty collection, the whole
collection is the drop target. The audit's H1 and H2 fix the rest,
whether or not the panel exists: name it on creation, and put a button
front and centre.

## Scrolling a window that's partly covered (Jason's idea)

The Timeline window can sit behind the main window, with its top
covered. The idea:

- **While covered:** the Timeline window adds padding at the top of its
  content, as tall as the part that's covered. The top rows can then be
  scrolled down into the visible part with a two-finger swipe, without
  bringing the window to the front.
- **Brought to the front:** the padding stays where it is, so nothing
  jumps. It's scrolled away like any content, and once it's scrolled out
  of view it's gone, and the content goes back to its normal size.

**The scene it's for (Jason):** a late stage of a show, played back
large in the main window. The Timeline window sits behind it, tall, with
only a row or two showing below the viewer. Swiping over that strip
scrolls every row past, so each can be seen against the playback without
disturbing it. To edit, click the Timeline window: it comes forward, the
edit is made, and a swipe brings the whole tool into view. Click the main
window, and the Timeline window drops behind again, ready to be swiped
through. It should feel like magic: covered or not, nothing in the
timeline is ever out of reach.

What's known before trying it:
- **Scrolling a window behind is already normal on the Mac.** A swipe
  scrolls whatever window is under the pointer, front or not, without
  activating it. So only the padding is new.
- **Knowing what's covered:** ShowTools knows where its own windows are
  and in what order. Other apps' window frames are readable too
  (`CGWindowListCopyWindowInfo`; bounds need no screen-recording
  permission). The covered height is where the covering windows' bottom
  edges fall across the Timeline window's top.
- **The padding:** `NSScrollView.contentInsets.top`, changed as windows
  move. The front-window behaviour takes the inset away only once the
  scroll position has passed it, adjusting the scroll position in the
  same step so the content doesn't jump.
- **Not standard Mac behaviour.** No app I know of does this, so it will
  want a harness first and a hands-on feel for it. The timeline scrolls
  only sideways today: vertical scrolling arrives with extra rows, and so
  does this.

## A possible order (not a plan)

1. ~~**The show session:** state out of the views.~~ — **done 2026-09-24**
   (`ShowSession.swift`, "What stands in the way" above). Changed nothing
   on screen, as expected; the menu work it was meant to simplify
   (`spec/hig-audit.md` batch 5) hasn't been revisited yet.
2. ~~**The Slide Editor,** as the first new window.~~ — **built 2026-09-24**
   (v1: the image, its handles, the full inspector — no playback controls;
   `spec/panekit.md`, "Step 4, first piece"). The collage maker still waits
   for it, since it isn't built yet either.
3. ~~**The library panel,** the second: it opens from the Library pane and
   moves nothing out of the main window.~~ — **built 2026-09-24**
   (`spec/panekit.md`, "Step 4, second piece"). Show in Library, which
   lands here, still waits on the right-click-menu work — it isn't built
   anywhere yet.
4. **One detachable area,** probably the inspector, to prove the pattern:
   undo, keys, and the main window closing up. Then the others.
5. **The timeline pane, detached,** last: it carries the most keys and
   playback.
