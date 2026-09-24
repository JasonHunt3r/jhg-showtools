# PaneKit — a reusable pane system for Mac apps

**Status:** Building. **Steps 1–3 done 2026-09-24.** Step 1: compiled and
tested clean on the Mac, and the harness's hands-on checks all passed,
Jason's own hands. Step 2: ShowTools' main window is on PaneKit —
`NavigationSplitView` is gone; the Library pane and the detail are a real
PaneKit split. Step 3: Edit Show's and Edit Slides' columns are on
PaneKit too — `ColumnsSplitView` and `VSplitView` are both gone, and
building Edit Show's three columns turned into `PaneNode.row(…)`, a
reusable recipe for a row of three independently-sized panes ("Building a
row" below) — not ShowTools-specific, since a second app hitting the same
shape shouldn't have to re-derive it. **Left:** step 4 (panes popping
out — the show session). PaneKit is a local package dependency now
(`Package.swift` and `project.yml`), named PaneKit, and lives in this
repo for now (settled, Jason).

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
  `near` is what's adjacent to it.
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
- **Undo follows:** a popped-out pane's window uses the main window's
  undo manager, so ⌘Z there undoes the same history (the Info panel's
  pattern, `InfoPanelWindow.sharedUndoManager`).
- **Keys follow:** the window-level keys an app sets up (ShowTools'
  Space, J, K, L) work in a popped-out pane's window too, since the app
  registers them with PaneKit rather than with one window.
- **What PaneKit can't do for the app:** a pane can only move between
  windows if what it shows lives *outside* its views. ShowTools' show
  session (`spec/windows.md`: the selection, the engine and the zoom,
  out of the views) is that app-side prerequisite. PaneKit moves the
  view; the app keeps the state.

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
   pane isn't in this tree yet — it needs the show session (state moved
   out of the views, step 4's own prerequisite), so it stays inside Edit
   Show's own `VSplitView` for now, untouched, until step 3 or step 4
   gets to it. Checked, real clicks: divider drag resizes the split;
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
     only floors, doesn't cap. **Closing the inspector now grows the
     list, not the preview** — a direct, visible consequence of the same
     nesting choice (list is the inner split's "main" side, so it
     absorbs whatever the inspector frees), confirmed by a real
     double-click collapse in the demo show.
   - **The vertical split** (columns row above the storyline, in place
     of `VSplitView`) has one known, minor mismatch: `Pane.minSize` is
     one number for both axes, so the preview's width-floor (420) also
     becomes the columns-row's height-floor for this split, versus the
     original 220. In practice this lands under the app's own minimum
     window height (700) with room to spare (measured: ~691 total), so
     it isn't reachable in the app's normal range, but it's the same
     kind of cross-axis leak, noted here rather than silently accepted.
4. **ShowTools' panes popping out** (`spec/windows.md`): the library
   panel, the inspector panel, the Timeline window. PaneKit already does
   the moving by then; this step is the show session, so the panes have
   their state to take with them.

## Settled

- **The name:** PaneKit (Jason, 2026-09-24).
- **The repo:** it stays in this one for now, as its own library target
  with no ShowTools dependencies (Jason). Lifting it out later stays
  easy.
