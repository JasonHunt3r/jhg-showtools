# PaneKit — a reusable pane system for Mac apps

**Status:** Building. **Steps 1–3 done 2026-09-24; step 4 (every pane
popping out — the Slide Editor, the library panel, the Inspector, the
Timeline pane) and step 5 (the timeline pane full width under the
Library pane too) both done 2026-09-25.** Step 1: compiled and
tested clean on the Mac, and the harness's hands-on checks all passed,
Jason's own hands. Step 2: ShowTools' main window is on PaneKit —
`NavigationSplitView` is gone; the Library pane and the detail are a real
PaneKit split. Step 3: Edit Show's and Edit Slides' columns are on
PaneKit too — `ColumnsSplitView` and `VSplitView` are both gone, and
building Edit Show's three columns turned into `PaneNode.row(…)`, a
reusable recipe for a row of three independently-sized panes ("Building a
row" below) — not ShowTools-specific, since a second app hitting the same
shape shouldn't have to re-derive it. Step 4's own prerequisite, the show
session, is also done (`spec/windows.md`, `ShowSession.swift`) — the
show's selection, engine and lane state moved out of `ShowView`'s and
`EditShowView`'s `@State` into one object `AppModel` owns, so nothing on
screen changed but a pane in another window now has something to read.
`.row` also gained `nearIsRigid` (found watching Jason use Edit Show:
`near`, the list column, now only changes size from its own divider —
"Building a row" below). PaneKit is a local package dependency now
(`Package.swift` and `project.yml`), named PaneKit, and lives in this
repo for now (settled, Jason).

**Step 4, first piece — the Slide Editor: built 2026-09-24**
(`Sources/ShowToolsApp/SlideEditorWindow.swift`). Jason picked the build
order (Slide Editor, then the library panel, then one detachable area) and
settled double-click in its favour over the inspector (`spec/conventions.md`
§"Double-click"). v1 scope, also Jason's call: the image with its
Transform/Rotation handles and the full inspector beside it — no playback
controls, since it's one slide, not the show; the collage maker and
clicking to aim the Pan and Zoom point stay Later (`spec/plan.md`).
Follows the Info panel's pattern (an `NSPanel` hosting SwiftUI, its own
`undoManager` override) rather than a new SwiftUI window scene, per
`spec/windows.md`'s note on the layout-loop crash. Owns its own
`PlaybackEngine`, paused on the one slide, so opening it never disturbs
the main window's preview and it works from Edit Slides too (which has no
engine running at all); retargeting to a different slide reuses the same
window rather than opening a second one. Opens from a double-click on a
slide in Edit Slides' list or the storyline, or "Open in Slide Editor" on
either's context menu. `swift test` (305) and `./make-app.sh` clean;
checked with axtool against a scratch library — both double-click paths
open it, retargeting reuses the window, Esc closes it, no new
`ShowTools-exception.log` entries — and **confirmed by Jason's own hands,
2026-09-24: "seems to work as expected."** **Left of step 4:** one
detachable area (probably the inspector), the timeline pane detached
last — `spec/windows.md`, "A possible order".

**Step 4, second piece — the library panel: built 2026-09-24**
(`LibraryPanel`/`LibraryPanelWindow`, `Sources/ShowToolsApp/Libraries.swift`).
Settled as a **panel** (floats above the app's other windows), per
`spec/windows.md` answer 3 — it's meant to float over a new, empty
collection so the whole panel becomes a drop target. Opens from "Open
Library Panel" on the Library item's context menu (previously stubbed
in, greyed out); moves nothing out of the main window, which keeps
showing its own Library grid exactly as before — it's a second window on
the same content, not a detach. It's the grid itself
(`LibraryGridView(collectionID: nil)`), not a second view, so narrow it's
a list and wide the grid's own tile-size slider grows the thumbnails —
`spec/windows.md` answer 6's guess confirmed rather than built new.
Follows `InfoPanel`'s pattern: an `NSPanel` hosting SwiftUI, its own
`undoManager` override, singleton (`show` brings the existing one
forward rather than opening a second). One thing `InfoPanel` didn't have
to solve: **`\.undoManager` isn't a writable environment key** on this
SDK (`\.environment(\.undoManager, …)` fails to type-check — "cannot
convert `KeyPath` to `WritableKeyPath`"), so `LibraryGridView` gained a
plain `undoManagerOverride: UndoManager? = nil` init parameter instead,
falling back to the ambient environment value when nil (unchanged for
every other caller). `swift build`, `swift test` (305) and `./make-app.sh`
all clean; checked with axtool against a scratch library, Jason's own
real copy left untouched throughout: the context menu item is enabled
(was disabled), opens a floating "Library" panel showing all 11 seeded
items with its search/filter/sort/tile-size bar, reopening brings the
same window forward rather than duplicating, Esc closes it, no new
`ShowTools-exception.log` entries. **Not yet checked by Jason's own
hands**, and Show in Library (which lands here per the plan) still waits
on the right-click-menu work that hasn't built that item anywhere yet.

## What it is

Our own pane layout, to replace the built-in split views, built once and
reused in every Mac app Jason makes, not rebuilt for each.

**The primitive is Finder's shape:** two panes and one divider. Anything
bigger is made by nesting that primitive. ShowTools' main window, with
the timeline pane edge to edge under the Library pane
(`spec/windows.md`):

```
split (top / bottom)
├─ split (left | rest)
│   ├─ Library pane                    closes to the left edge
│   └─ the detail: the grid, Edit Slides' columns, or Edit Show's
└─ Timeline pane                       edge to edge; closes to the bottom
```

Either tree is two lines of code once the primitive exists. That's the
point.

## What it replaces, in Swift's words

A **class** makes **objects**: long-lived things with an identity. AppKit's
views are objects. A **struct** is a value, closer to a description:
SwiftUI views are structs, and SwiftUI builds the real objects behind
them.

| What | Kind | Where | What happens to it |
|---|---|---|---|
| `NavigationSplitView` | SwiftUI container view (a struct) | the main window: the Library pane beside the rest | **Replaced** by PaneKit |
| `VSplitView` | SwiftUI container view (a struct) | Edit Show: the line between the columns and the timeline pane | **Replaced** by PaneKit |
| `.inspector()` | SwiftUI view *modifier* | was on Edit Slides | **Already gone** (the crash fix) |
| `ColumnsSplitView` | AppKit class, a subclass of `NSSplitView` | Edit Show's and Edit Slides' columns | **Grown into PaneKit:** it's the seed |
| `ShowColumns`, `TwoColumns` | SwiftUI structs that wrap `ColumnsSplitView` | the same two places | Replaced by PaneKit's own wrapper |

**Would rebuilding `.inspector()` from its parts show why it crashed?**
Probably not. We rebuild its *behaviour* from public parts, not Apple's
private code. The crash was in SwiftUI's private size negotiation
between the inspector column and its neighbour, which never settled.
PaneKit sizes panes itself, with no negotiation, so it shouldn't
reproduce the crash. That it doesn't is itself evidence that the
negotiation was at fault. To learn the real *why*, a tiny app with only
`.inspector()` in a `NavigationSplitView`, run on macOS 26 and 27, would
isolate it. If only 27 crashes, report it to Apple (Feedback
Assistant). Not needed for our fix.

## Why our own (settled, 2026-09-24)

- **The built-ins decide too much.** `NavigationSplitView`'s left pane
  always runs full height, so the timeline pane can't go edge to edge.
  Its collapse leaves nothing to grab, which is how Jason lost the
  Library pane.
- **The built-ins have bitten.** The layout-loop crash was SwiftUI's
  `.inspector()`. `NSSplitViewController` with holding priorities lets
  the lowest-priority pane absorb every divider drag (measured
  2026-09-21).
- **Ours already works.** `ColumnsSplitView` has run Edit Show and Edit
  Slides reliably since the crash fix. PaneKit is that, generalised.
- **Code is cheap for Claude; checking isn't.** Built once, checked once,
  reused everywhere, the checking is paid once too.

## What every pane can do

**Measured and proven in `ColumnsSplitView`, kept as they are:**
- A divider drag resizes only the two panes beside it.
- A window resize goes to the **main** pane of each split. The other
  keeps its size.
- Closing a pane keeps the other panes' sizes. Reopening it restores its
  last size.
- Sizes are remembered between launches, but only from a real drag. A
  squeeze from a narrow window never becomes the remembered size.
- Dividers are drawn clear, with the split's background showing through
  a 1-point gap. NSSplitView's own divider layers go stale with a manual
  layout (found by a layer-tree dump, 2026-09-21).
- The grab strip is wider than the line drawn.
- Each pane's content is hosted in a view that takes the mouse **only
  inside its own frame** (`ColumnHost`). SwiftUI hit-tests content past
  its edges otherwise, and steals the neighbour's clicks and scrolling.

**New:**
- **Closes to its edge, on purpose,** leaving an **edge handle**: thin,
  always visible, clickable. Drag it to open or resize; double-click it
  to open or close (`spec/conventions.md`). The frame strip's 12-point bar
  with its capsule is the model.
- **A minimum and a maximum** per pane (the Library pane's 180 to 360,
  say), and a default size.
- **Commands for free:** each closable pane gets a Show/Hide menu item
  (View menu) with an optional shortcut, and the state a toolbar button
  can bind to.
- **Restore Defaults and presets:** put every pane back to its default,
  or to a named preset. The levels (Basic, Advanced, "Bring it on!") are
  presets (`spec/simple-things-fast.md`). So is View ▸ Restore Default
  Layout, which today is `DefaultLayout.swift`.
- **Keyboard focus** moves between panes with Tab and ⇧Tab, and a
  closed pane is skipped.
- **Pops out, and back in** (Jason, 2026-09-24: built in, not added
  later). See the next section.
- **Switches sides — built 2026-09-25** (Jason: "basically we're
  reordering the columns"). Drag a pane's divider, or its closed handle,
  across the main side: it grows into main's space, and once what's left
  between the pointer and the far edge is less than the pane's own size
  at the start of the drag, the two trade places — the pane mounts on the
  **opposite** edge of its split (leading ⇄ trailing, top ⇄ bottom), open,
  at that starting size. Dragging back the same way switches it back,
  within the same drag or a later one. `Split.canSwitchSides` (default
  **true**, like `collapsible`); which side it's on is state,
  `SplitState.onOtherSide`, saved with its size, and Restore Default
  Layout puts it back. Pure arithmetic in `dragResize`
  (`PaneContainerView.swift`), pinned by `PaneControllerTests`'s
  "Switching sides". **Limits:** a pane switches within its own split,
  so the nesting decides where it can go (Edit Show's Browser can reach
  the preview's far side, not past the inspector); `.row`'s two splits
  don't switch (their linked arithmetic assumes fixed sides); no menu
  command yet, and no animation — it jumps.
- **The app's own view as the handle — built 2026-09-26** (Jason, for
  ShowTools' viewer drawer: "we can just use the existing header bar as
  the handle box"). A split with `handle: .external` takes no room when
  closed — no edge handle, no divider — and the app puts a
  `PaneHandleView` behind its own view (AppKit), or marks it with
  `.paneHandle(controller, split:)` (SwiftUI), so the view's empty space
  drags the split and a double-click opens or closes it; its controls keep
  their own clicks. A drag follows the pointer from wherever it grabbed
  (`handleDragExtent`), rather than jumping to it as an edge line does.
  Such a split can't switch sides (`canSwitchSides` is forced off).
  `PaneHandle.swift`; `PaneHandleTests` (8); the harness's "A header bar
  as the handle" layout. Checked by Jason's hands in the harness, and
  with axtool: closed leaves the bar at the very top; a 200-pt drag gave
  a 200-pt drawer (±1, no jump); dragging up closes it; double-clicks
  toggle; the search field types and the button's double-click doesn't
  toggle.

## Building a row (added 2026-09-24)

The primitive is strictly two panes. Three or more independently-sized
siblings in a row — a common shape (Mail, Xcode's navigator/editor/
inspector, this app's own Edit Show) — take two or more nested splits, and
the nesting forces a nontrivial choice with no single right answer: which
pane absorbs a squeeze first when the window's too narrow for all of them,
and which divider moves what. **`PaneNode.row(…)`** (`PaneModel.swift`)
captures the answer that keeps both of a pane's promises — a divider only
moves its own two neighbors, and a resize goes to `main` — for a row of
three: `main`, `near` (next to it) and `far` (the outer edge). It's built
from finding this out the hard way for Edit Show's preview/list/inspector
(`spec/edit-slides-inspector-port.md`'s successor decision below), so a
future app gets the recipe instead of re-deriving it:

- `near` gives way before `far` as the window narrows (`main` shrinks
  first, being main; `near` has no cap, only a floor; `far` alone keeps a
  real, independently-remembered range).
- Closing `far` (only it can) hands its space to `near`, not `main` —
  `near` is what's adjacent to it. **Under `nearIsRigid`, this flips: the
  space goes to `main` instead**, so `near` stays exactly as unmoved by a
  collapse as it already was by a direct drag (added 2026-09-25, item 1,
  `ShowTools Feedback — Worklist for Next CC Session.md` — see `PaneModel
  .row`'s own doc comment).
- This is one specific, opinionated trade — not the only one a three-pane
  row could make (an app could instead cap both `near` and `far` and give
  `main` the far end of the row, the way Mail's own three columns read;
  the harness's Mail shape does this, and a comment on it notes what that
  costs: the mailboxes|list divider ends up moving the *message* pane, not
  list, since list is protected as the inner split's own sized side).
  `.row` is what covers ShowTools' real case, checked against a real
  demo show, not a general theory of rows — a fourth call worth adding if
  a second real shape needs a different trade, not before.
- Proven, not just typed: `PaneKitTests.testRow*` pin the arithmetic;
  `EditColumnsLayout.threeColumns` (ShowTools) and the harness's `.showTools`
  case both build from it now, replacing hand-nested splits that said the
  same thing three separate times.

### `nearIsRigid`: a relationship between two panes, not just a shape

Found the same day, watching Jason use Edit Show: `near` (the list
column) had no divider of its own that left it alone. Dragging the
main|near divider correctly resized `near`; dragging near|far also
resized `near`, which felt wrong to him — a divider on the *inspector's*
edge changing the *list's* width. What he wanted: **`near` only ever
changes size from its own (main|near) divider.** Dragging near|far should
reach past it to resize `main` and `far`, with `near` sliding to stay
adjacent to `far`, unchanged.

This is a relationship between `near` and `far`'s divider, not a new
shape, so it's a flag on `.row` — `nearIsRigid: Bool` — not a new tree
shape. **How it works:** `Split` gained `linkedAncestor: String?`. When a
split's own divider is dragged and it names a `linkedAncestor`, the same
delta lands on that split's stored size too (`trackResize`,
`PaneContainerView.swift`) — so if `far` grows by 12, the near+far combo
(the outer `.row` split's own sized side) also grows by 12, and `near`,
computed as the combo's total minus `far`, comes out unchanged. Only
`trackResize` — the AppKit-side drag handler — knows this option exists;
`PaneLayout`'s pure arithmetic doesn't, and didn't need to change.

**Where the two panes still meet reality:** if `main` doesn't have enough
slack left to absorb the whole delta before hitting its own floor, `near`
absorbs the shortfall rather than the drag simply refusing to move —
measured in the app (dragging inspector wider than preview's remaining
slack allowed put some of the growth on list after all). This isn't a
bug: a rigid pane can only stay rigid while there's somewhere else for
the change to go.

**ShowTools no longer uses `.row` (2026-09-25, item 13).** Edit Show's
Browser had to become a drawer, and `near` is the inner split's main side,
so it can't close. `EditColumnsLayout.threeColumns` is now two splits
nested from the right — the inspector's split outside, the Browser's
inside, preview as the innermost main — so both close to their own handle
(stacked at the right edge when both are closed), and `nearIsRigid`'s
promise comes free: every change on either goes to preview. `.row`,
`nearIsRigid` and `linkedAncestor` stay in PaneKit, tested and used by the
harness. The paragraph below is the history of the Edit Show case.

Wired into `EditColumnsLayout.threeColumns` (`nearIsRigid: true`) and
checked with real drags against a demo show: near|far now moves preview
and the inspector, list only slides; main|near still resizes list
directly, unaffected. `PaneKitTests.testRowNearIsRigid*` pin the
arithmetic the same way the rest of `.row` is pinned.

## Pane ⇄ panel: popping out, built in

Any pane can leave the window for a window of its own, and go back. This
is the pop-out logic from `spec/windows.md`, owned by PaneKit so every
app gets it.

- **Each pane declares how it pops out:**
  - as a **panel**, which floats above the app's other windows (the
    library, the inspector);
  - as an **ordinary window**, which can go behind (the Timeline window);
  - or **not at all**.
- **The main window closes up** when a pane leaves: its neighbours take
  the space, exactly as when it closes to its edge. **Its slot is kept**,
  so putting it back returns it where it was, at its old size.
- **Ways out and back:**
  - a menu command (View ▸ Show Inspector in Window, say);
  - a button on the edge handle;
  - **putting it back:** the window's own button, the menu command, or
    closing the window, if the pane asks for that.
  - Dragging a pane out by its edge handle, and back in, is a candidate
    to try in the harness.
- **Remembered between launches:** which panes are out, and where their
  windows sit, at what size (settled: launch restores everything,
  `spec/windows.md`).
- **Undo follows — fixed 2026-09-25, in the app, not PaneKit.** First
  measured broken: an edit made from the popped-out Inspector saved
  correctly and was undoable from the **main** window, but `Edit ▸ Undo`
  read disabled outright while the popped-out window was key, and a real
  ⌘Z there did nothing — even though `PanePanel.undoManager` provably
  returned the identical `UndoManager` object (`ObjectIdentifier`), and
  even with `canBecomeKey` also overridden (the Info panel's own fix,
  `InfoPanel.swift`) — neither was enough. **Cause, confirmed by the
  fix working:** SwiftUI's own automatic Edit ▸ Undo/Redo commands are
  scoped to its `Scene` graph; a `PanePanel` is a raw AppKit window built
  outside that graph (`PaneWindowController`, imperative), so those
  commands never see it, regardless of what `window.undoManager` itself
  returns. **The fix:** `ShowToolsApp.swift`'s `UndoMenuState` replaces
  SwiftUI's automatic commands with `CommandGroup(replacing: .undoRedo)`,
  asking `NSApp.keyWindow?.undoManager` directly and refreshing on
  `NSWindow.didBecomeKeyNotification` plus `NSUndoManager`'s own
  checkpoint/did-undo/did-redo notifications (Foundation's overlay
  doesn't vend these as `NSUndoManager` statics, so they're constructed
  by their ObjC string names). Checked with axtool against a scratch
  library: `Edit ▸ Undo` now reads "Undo Move" (the real action name,
  live) while the popped-out window is key, and a real ⌘Z there reverts
  the edit (confirmed against the saved show's JSON), ⇧⌘Z redoes it. This
  is an app-level fix, not a PaneKit one — PaneKit's job stops at making
  `window.undoManager` correct, which it already did; an app that still
  uses SwiftUI's own automatic Undo/Redo would need the same
  `CommandGroup` replacement to get a pop-out's ⌘Z working. Untested:
  whether the Info panel or the Rhythm tool (built the same imperative
  way, before this fix existed) had the same gap — they now share this
  app-wide fix regardless, so it doesn't matter going forward.
- **Keys follow:** the window-level keys an app sets up (ShowTools'
  Space, J, K, L) work in a popped-out pane's window too, since the app
  registers them with PaneKit rather than with one window.
- **What PaneKit can't do for the app:** a pane can only move between
  windows if what it shows lives *outside* its views. ShowTools' show
  session (`spec/windows.md`: the selection, the engine and the zoom,
  out of the views) is that app-side prerequisite. PaneKit moves the
  view; the app keeps the state.

**A control shared between a pane and its pop-out, considered and set
aside (Jason, 2026-09-24):** the library panel's own tile-size slider was
built sharing one `@AppStorage` key with the main window's grid, so
dragging either slider moved both windows' thumbnails together. Fixed in
the app, not PaneKit (`LibraryGridView.tileSizeKey`, `Libraries.swift`) —
each window gets its own key, so the panel can sit in list view while the
main window stays at its own size. Jason's instinct: since this is the
kind of thing that could recur in a *real* pop-out (an inspector's own
control, once item 4 builds it), should PaneKit grow a
`controlLinked: Bool`-style declaration for it? **Set aside, and worth
re-reading if this comes up again:** a true pop-out (`spec/windows.md`'s
"1. Areas that can leave the main window") moves the *same* view instance
out of the main window — the pane's slot in the main window sits empty
while it's out (above), so there's only ever one instance of its
controls, and no linked-or-not question to ask. The library panel isn't
that: it's a *second*, independent window on the same content, opened
from a menu, that the main window keeps showing too — the case where the
question can even arise is narrower than it first looks, since it needs
both copies on screen at once, which today only the library panel does.
If a second real case turns up — some future window that, like the
library panel, duplicates a pane's content rather than relocating it —
it's still probably an app-level convention (a keyed `@AppStorage`
parameter, as here) rather than a PaneKit feature: PaneKit's own line
above is that it moves views, not the state inside them, and a
linked/independent flag would mean it starts knowing about that state.

## What's known, and how sure (checked 2026-09-24)

These are things to know while building it, each at the strength it was
found. Only the confirmed ones are rules.

**Confirmed:**
- **`.inspector()` crashed here.** SwiftUI's inspector modifier on Edit
  Slides was the layout-loop crash's cause. Removing it stopped the
  crash, and the port off it has held
  (`spec/history/2026-09-23-crash-hunt-session3.md`). PaneKit replaces
  what it did (below).
- **Per-window undo.** A separate window's undo manager isn't the main
  window's, and ⌘Z asks the key window's (showtools-gotchas, measured). A
  popped-out pane shares the main one.
- **`ColumnsSplitView`'s rules** listed above (divider drags, window
  resize, collapse, remembered sizes, clear dividers, `ColumnHost`). Each
  was measured.

**Current OS behaviour, which may change:**
- **macOS 27 aborts a window that asks for layout again from inside its
  own layout pass.** Several projects report it as new in macOS 27 and
  have worked around it (`spec/history/2026-09-24-crash-hunt-debrief.md`).
  It may be a regression that a macOS update fixes. **Before building a
  workaround, check whether the macOS in use still does it**, with a small
  harness case, and date what was found. Keep any workaround small and
  labelled, so it's easy to take out.

**Unproven, from before the crash's cause was found (not rules):**
- *"One change per run-loop turn"* when several panes move at once. It
  came from Restore Default Layout raising the exception on 2026-09-23,
  before `.inspector()` was found. That was probably the same crash, so
  it proves nothing about pane moves. PaneKit replaces it with layout
  transactions (below).
- *"No SwiftUI measuring containers in a pane."* `ViewThatFits` was
  cleared outright (showtools-gotchas: "nothing should be read into its
  removal"). Only `.inspector()` is confirmed.

### Layout transactions: every change at once (Jason, 2026-09-24)

Restore Default Layout staged its changes a run-loop turn apart because
it was poking three layout systems that don't talk to each other: the
window's frame, SwiftUI's split view, and `ColumnsSplitView`. Each change
set off another system's own layout. With PaneKit owning every pane,
there's one system:

1. **Set everything in the model:** every pane's size, open or closed,
   in or popped out.
2. **Lay out once**, in one pass, the way `ColumnsSplitView.arrange()`
   places every column from its stored widths.
3. **Broadcast once** that the layout changed, for anything that
   follows it (the toolbar buttons, the menu items, a saved preset).

A preset, a level switch, Restore Defaults, or a pane popping out is one
transaction. No half-moved state is ever drawn, and no system sets off
another. If the window's own size changes too, that goes first, then
the one pass.

### What we lose by not using `.inspector()`

Only what it did for us, which PaneKit defines itself:
- **A trailing pane** that shows and hides with an animation → a PaneKit
  pane with `edge: .trailing`.
- **A width range** (minimum, ideal, maximum) that the user drags within
  → the pane's `size` and `range`.
- **A toolbar toggle** that stays in step with it → the pane's Show/Hide
  command and state, which a toolbar button binds to.
- **Its own sizing negotiation with the window.** That's the part that
  looped. PaneKit sizes its panes itself, the way `ColumnsSplitView`
  does.
- (On iPhone and iPad it also turns into a sheet. That doesn't apply to
  a Mac app.)

Nothing it offered is out of reach. Edit Slides' and Edit Show's
inspectors already work without it.

**The public parts it's assembled from, which PaneKit uses directly**
(`.inspector()` itself is sealed, so it can't be taken apart; these
are the same parts Apple builds from):
- the translucent sidebar material: `NSVisualEffectView`;
- the show/hide animation: `NSAnimationContext` (`ColumnsSplitView`
  already uses it);
- the toolbar toggle: a toolbar button bound to the pane's state;
- focus moving between panes: AppKit's key-view loop;
- VoiceOver: AppKit's accessibility roles for a split and its panes.

## A sketch of how an app would use it

Not an API yet, just the feel it should have:

```swift
PaneSplit(.vertical, id: "window") {                // top / bottom
    PaneSplit(.horizontal, id: "top") {             // left | rest
        Pane("library", edge: .leading, size: 219, range: 180...360) {
            LibraryPane()
        }
        Pane.main { Detail() }
    }
    Pane("timeline", edge: .bottom, size: 260, range: 160...600) {
        TimelinePane()
    }
}
```

Each `Pane` with an `edge` can close against it and gets its handle,
its remembered size (under its `id`) and its menu command. `Pane.main`
takes what's left.

## What was built (2026-09-24, uncompiled)

General, not ShowTools-specific (Jason: "ShowTools is the specific example
from which to generalize other morphologies"). The harness shows three
shapes from the one primitive: Finder's two panes, Mail's three columns,
and ShowTools' layout with the timeline under everything.

- **`PaneModel.swift`:** the tree. `PaneNode` is `.leaf(Pane)` or
  `.branch(Split)`, built with `.pane(…)` and `.split(…)`. A split has an
  axis, a **sized** side (keeps its size, closes against its edge) and a
  **main** side (takes the rest), a default size and a range. The state
  (`PaneKitState`: each split's size and whether it's closed; each pane's
  popped-out flag and window frame) decodes field by field. An empty
  state is the default layout, and a preset is just a state.
- **`PaneLayout.swift`:** pure arithmetic from tree, state and rectangle to
  frames, dividers and handles. It keeps sizes inside their range and the
  main side above its minimum, and a squeeze never changes the stored
  size. A closed side leaves a 12-point handle; a side whose panes have
  all popped out closes up. This is what the tests pin.
- **`PaneController.swift`:** `@Observable`, owns the state, and every
  change is one transaction (`perform`: set, lay out once, save, broadcast
  once). Toggle, pop out and put back, Restore Defaults, apply a preset;
  drags draw live and commit on release. Saved in the preferences as
  `PaneKit.<id>`. `menuItems()` gives an AppKit app its View-menu section.
- **`PaneContainerView.swift`:** the AppKit view. Frames come from the
  arithmetic in one pass (`layout()`), with no constraints between panes,
  so there's no size negotiation to loop. Hosts take the mouse only in
  their frame (`ColumnHost`'s lesson). Dividers draw a 1-point line with a
  wider grab strip. Edge handles draw the frame strip's bar and capsule:
  drag to open, double-click to open. Double-clicking a divider closes its
  side.
- **`PaneWindows.swift`:** popped-out panes' windows: a floating panel or
  an ordinary window, sharing the main window's undo manager. Closing one
  puts the pane back in its slot; its frame is remembered.
- **`PaneLayoutView.swift`:** the SwiftUI bridge, with hosting views set
  to `sizingOptions = []` so SwiftUI doesn't negotiate sizes.

**Not in this first cut** (noted for later): keyboard focus moving
between panes (the key-view loop); an app's window-level keys reaching a
popped-out window (`poppedOutWindows` is there for the app to use);
dragging a pane out by its handle to pop it out; animation of a pane
opening or closing (changes are instant for now).

## Where it lives

- **Now:** its own Swift package inside this repo, `PaneKit/`, depending
  on nothing in ShowTools, so the boundary is real from day one. ShowTools
  will add it as a local package dependency when its main window moves
  onto it (step 2).
- **Later:** lifted into its own repo, and added to other apps as a
  package.

## The order

1. **Harness:** a standalone app (`PaneKit/Harness`)
   with the ShowTools tree above and dummy content. Check:
   - dragging, closing to each edge, the handles, double-click;
   - popping a pane out as a panel and as a window, and putting it back
     in its slot;
   - remembered sizes and window positions across a relaunch;
   - window resize, and Restore Defaults;
   - no layout-loop exception under rapid changes.

   It's run on the Mac by the Claude Code there, and felt by Jason.
2. ~~**ShowTools' main window** on PaneKit: the Library pane and the
   full-width timeline pane. `NavigationSplitView` goes.~~ — the
   Library-pane-and-detail half is **done 2026-09-24**
   (`MainView.layout`, a two-pane split: `.pane("library", …)` and
   `.pane("detail", …)`, `AppModel.mainPanes`). The full-width timeline
   pane came later, once the show session existed to read from —
   **built 2026-09-25**, when it turned out the first build of step 5
   (below) had only ever put it under the detail column, not the whole
   window, missing this step's own goal (found from a plain description
   of the bug: "the timeline is supposed to go the whole width under the
   library column"). `AppModel.mainPanes`'s root is now a vertical split
   wrapping the library|detail split, with `.pane("storyline", …)`
   sized to it, not inside `model.editShowColumns` any more — see step
   5's own entry for the move and what it took. Checked, real clicks: divider drag resizes the split;
   drag-to-edge leaves the handle and reopening restores the dragged
   size; ⌘Z through the pane undoes a delete (the AppKit-boundary
   undo-manager question — resolved via the window's own responder
   chain, not the SwiftUI environment, so no explicit passing needed);
   View ▸ Restore Default Layout puts the pane back to its default width
   in one transaction; View ▸ Show Library toggles it. `xcodebuild` for
   the ShowTools scheme, `./make-app.sh debug` and `swift test` (305
   tests) all clean.
3. ~~**Edit Show's and Edit Slides' columns** on PaneKit: `ColumnsSplitView`
   and `VSplitView` go.~~ — **done 2026-09-24**
   (`ShowColumns.swift` → `EditColumnsLayout`, `AppModel.editShowColumns`
   and `.editSlidesColumns`). Both files (`ColumnsSplitView.swift`, the
   old `ShowColumns`/`TwoColumns`) are gone. Edit Show's three columns are
   built from **`PaneNode.row`** (generalized right after, below, once the
   choice below was made and proven against this real case).

   Edit Show's three columns (preview, list, inspector) aren't PaneKit's
   binary primitive done once — they're two nested splits, and the
   nesting forces a choice PaneKit's own docs don't make for you
   (**settled, Jason, 2026-09-24: divider isolation**, over exactly
   matching `ColumnsSplitView`'s old narrow-window squeeze order):
   - **What's preserved exactly:** dragging the preview↔list divider
     touches only those two, never the inspector; dragging the
     list↔inspector divider touches only those two, never the preview;
     a window resize goes to preview; sizes remembered only from a real
     drag; Restore Default Layout resets both trees in one transaction
     each. All checked with real clicks and a real demo show
     (`tools/make-demo-show.sh`), not just the type-checker.
   - **What changed, on purpose:** in a window too narrow for all three
     columns at their floors, list now gives way before the inspector
     (the reverse of before) — reachable only well below the app's own
     minimum window size. The list column lost its old upper bound
     (420): it's the "main" side of its own split now, which PaneKit
     only floors, doesn't cap. **Closing the inspector grew the list,
     not the preview, at first** — a direct, visible consequence of the
     same nesting choice (list is the inner split's "main" side, so it
     absorbs whatever the inspector frees), confirmed by a real
     double-click collapse in the demo show 2026-09-24. **Reversed
     2026-09-25** (item 1, `ShowTools Feedback — Worklist for Next CC
     Session.md`): Jason's own feedback the next day called this
     wrong — the list column should stay put and the preview should
     grow, matching what `nearIsRigid` already did for a direct near|far
     drag. `PaneController.setOpen` now applies the same
     `linkedAncestor` delta on a collapse/reopen that `trackResize`
     applies on a drag (`spec/panekit.md`'s own "Building a row" section
     has the current, corrected description).
   - **The vertical split** (columns row above the storyline, in place
     of `VSplitView`) has one known, minor mismatch: `Pane.minSize` is
     one number for both axes, so the preview's width-floor (420) also
     becomes the columns-row's height-floor for this split, versus the
     original 220. In practice this lands under the app's own minimum
     window height (700) with room to spare (measured: ~691 total), so
     it isn't reachable in the app's normal range, but it's the same
     kind of cross-axis leak, noted here rather than silently accepted.
4. **ShowTools' panes popping out** (`spec/windows.md`): the inspector
   panel, the Timeline window. PaneKit already does the moving; the show
   session — its own prerequisite, so the panes have their state to take
   with them — is **done 2026-09-24** (`ShowSession.swift`). The Slide
   Editor and the library panel are both built (above). **Edit Show's
   inspector, the first detachable area proper (`spec/windows.md`, "A
   possible order," step 4): built 2026-09-25** (`EditColumnsLayout
   .threeColumns`, `far: Pane("inspector", ..., popOut: .panel)`; View ▸
   "Inspector in Its Own Window," `ShowToolsApp.swift`). `swift test`
   (306) and `./make-app.sh` clean. Checked with axtool against a scratch
   library: pops out to a real `NSPanel` beside the main window (position
   matches the "beside the main window" formula exactly), the main
   window's list column grows to fill the vacated space (`PaneLayout
   .isEmpty`, already generic — no ShowTools-specific code needed),
   selecting a slide in the main window live-updates the popped-out
   content (the show session already shared), and an edit made from it
   (a Position X drag) saves to the library correctly. Undo was a real
   gap, found and fixed the same session — see "Pane ⇄ panel" above and
   `UndoMenuState`. Edit Slides' own inspector stays inline; this is the
   first case, not a port of both.
5. **The timeline pane, last: built 2026-09-25** (`EditColumnsLayout
   .editShowTree`, `.pane("storyline", ..., popOut: .window)`; View ▸
   "Timeline in Its Own Window"). Pops out as an ordinary window, not a
   panel — it can go behind, per its own table entry above. `swift test`
   (306) and `./make-app.sh` clean. Checked with axtool against a scratch
   library: pops out at the storyline's own width, the columns above grow
   to fill the vacated height (`PaneLayout.isEmpty` again, no new code),
   Undo/Redo work from it (the same `UndoMenuState` fix, confirmed with a
   real Set Range In from the popped-out window and a real ⌘Z undoing it).
   **Bare-key shortcuts follow it — a second, harder gap found and
   fixed:** `shortcuts(engine)` (Space, J/K/L, M, I, O, N, arrows) was
   attached to the outer view, outside `PaneLayoutView`, so it never
   moved with the pane; moving it onto the storyline pane's own content
   in the `content: [...]` dictionary let `SingleKeys`' existing
   `viewDidMoveToWindow` override re-attach its key monitor to whichever
   window the pane is actually in — confirmed with a real Space keypress
   toggling playback from the popped-out window. **`editShowCommands` —
   found broken, fixed the same day:** it read disabled outright for
   every Show/View menu item (Play/Pause, Add Marker, Set Range, Zoom, Go
   Back/Forward, Loop) while the popped-out Timeline window was key —
   the same class of bug `UndoMenuState` fixed for Undo/Redo:
   `.focusedSceneValue` is Scene-graph-scoped, same as SwiftUI's
   automatic Undo/Redo, and a PaneKit pop-out sits outside that graph.
   **The fix:** `EditShowCommandsValue` moved off `@FocusedValue`/
   `.focusedSceneValue` onto a plain stored property, `AppModel
   .editShowCommands` (matching how `editShowColumns`/`mainPanes`
   already live there) — `EditShowView` sets it via `.onChange(of:
   CommandsTrigger, initial: true)` rather than writing it directly in
   `body` (SwiftUI doesn't allow mutating `@Observable` state during a
   view update), reading the trigger from the saved `show`, **not**
   `engine.show`, to avoid `PlaybackEngine.show`'s own
   `@ObservationIgnored` trap (showtools-gotchas) silently freezing it;
   `.onDisappear` clears it, matching the old `@FocusedValue`'s own
   absence outside Edit Show. The `FocusedValueKey`/`FocusedValues`
   plumbing is gone; `AppCommands` reads `model.editShowCommands`
   directly. Checked with axtool against a scratch library, all from the
   popped-out Timeline window: Loop Playback toggled through the menu and
   the saved show's `editor.loopPlayback` flipped; Set Range In through
   the menu wrote `editor.rangeIn`; Go Back went from disabled to enabled
   after a real arrow-key nudge, matching its history correctly.

   **Moved to the main window's own tree — built later the same day,
   2026-09-25**, once it was clear this first build only ever gave the
   timeline pane the detail column's width, not the window's — missing
   the "full width under the Library pane too" step 2 always meant
   (`spec/windows.md`, "The idea"; `panekit.md`'s own sketch under "What
   it is"). `EditColumnsLayout.editShowTree` is gone; `EditColumnsLayout
   .threeColumns` is Edit Show's whole tree again. `AppModel.mainPanes`'s
   root wraps the library|detail split in a new outer vertical split
   (`"window"`, sized `.second`; the library|detail split **keeps the id
   `"main"`**, so Jason's already-saved sidebar width keeps its meaning),
   with `.pane("storyline", …, popOut: .window)` as the timeline pane.
   `MainView` renders it (`timelinePane`), reading the same
   `ShowSession`/`AppModel.timeline(for:)`/`AppModel.update` that
   `ShowView`/`EditShowView` already do, rather than either of those
   handing this view something pre-built — writing `@Observable` state
   from one view's `body` for another to read in the *same* update pass
   is the same class of trap the "don't mutate state during a view
   update" rule exists for, so `EditShowTimelinePane`
   (`Sources/ShowToolsApp/EditShowTimelinePane.swift`) was pulled out of
   `EditShowView` into its own file instead, with everything about the
   transport/storyline that isn't the engine's own lifecycle (range,
   arrow keys, row navigation, Go Back/Forward, `editShowCommands`) — the
   engine's creation and shutdown stay in `EditShowView`, which
   `EditShowTimelinePane` just reads (`session.engine`).

   **Two real bugs found and fixed while moving it, both before this
   landed:**
   - **A ⌘Delete/Delete race, not visible until the pane became a true
     main-window sibling.** `EditShowTimelinePane` had its own
     `.onDeleteCommand` for the lane's selection (markers, a song, an
     overlay, a transition, slides); `MainView`'s own `SingleKeys` already
     had a *different* Delete/⌘Delete handler, for the sidebar (Delete
     the selected show/collection/group). Once the timeline pane was a
     real `SingleKeys` instance living directly under `MainView`'s own
     tree rather than nested two levels inside `EditShowView`, pressing
     Delete with a slide selected in the storyline sometimes deleted the
     *entire show* instead — caught by hand with axtool (a "Delete
     'Test Show'?" alert, not the slide-removal notice), not by reasoning
     about it first. Two separate `NSEvent.addLocalMonitorForEvents`
     instances on the same window racing for the same keypress, with no
     defined winner. **The fix:** one handler, not two —
     `SlideActions.removeSelected(session:mutate:)` (`ShowView.swift`)
     carries the lane's own priority order now, called first from
     `MainView`'s existing sidebar handler; it returns `false` when
     nothing in the lane is selected, so the sidebar's own Delete/⌘Delete
     meaning is still the fallback. `EditShowTimelinePane` no longer
     handles Delete/⌫ at all.
   - **A popped-out Timeline window left open and blank after leaving
     Edit Show.** `MainView` closes the pane's *split* when
     `isEditingShow` goes false, but a popped-out pane's own window isn't
     part of that split any more — closing a split its pane has already
     left doesn't close that pane's window. Caught with axtool: popping
     the Timeline out, then View ▸ Edit Slides, left an empty "Timeline"
     window on screen. Fixed by putting the pane back first
     (`model.mainPanes.putBack("storyline")`) whenever `isEditingShow`
     goes false, ahead of collapsing the split.

   Checked with axtool against a scratch library, the whole path: the
   timeline pane sits at `(0, y, windowWidth, height)` — under the
   Library pane too, not starting at the detail column's left edge; the
   library and detail panes grow to fill the window's full height when
   Edit Slides or the plain Library view collapses the timeline away;
   switching back to Edit Show restores it, docked, full width; popping
   it out still works (an ordinary window, now at the pane's own full
   width); Undo/Redo and the Show/View menu commands still work from the
   popped-out window (unchanged fixes, re-confirmed after the move); a
   real slide Delete from the (now full-width, still-nested) storyline
   shows the slide-removal notice and removes just that slide, not the
   whole show; ⌘Z puts it back.

## Settled

- **The name:** PaneKit (Jason, 2026-09-24).
- **The repo:** it stays in this one for now, as its own library target
  with no ShowTools dependencies (Jason). Lifting it out later stays
  easy.
