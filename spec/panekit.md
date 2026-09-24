# PaneKit — a reusable pane system for Mac apps

**Status:** Planned (Jason, 2026-09-24). Nothing is built. **Left:**
everything, starting with a standalone harness. "PaneKit" is a working
name.

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

## Lessons it bakes in, so no app has to learn them again

- **Never ask for layout from inside layout.** macOS 27 kills a window
  that does (`spec/history/2026-09-24-crash-hunt-debrief.md`). Size
  changes that arrive during a layout pass wait for the next turn of the
  run loop.
- **One change per run-loop turn** when several panes move at once. Doing
  all of Restore Default Layout in one pass raised the layout-loop
  exception on 2026-09-23 (`DefaultLayout.restore`).
- **No SwiftUI measuring containers** (`ViewThatFits`, `.inspector()`)
  inside a pane's own layout.
- **Per-window undo:** a separate window's undo manager isn't the main
  window's, and ⌘Z asks the key window's (showtools-gotchas). A popped-
  out pane shares the main one, above.

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

## Where it lives

- **At first:** its own SwiftPM library target in this repo
  (`Sources/PaneKit`), depending on nothing in ShowTools, so the boundary
  is real from day one. `spec/layout.md` gets it when it's built.
- **Later:** lifted into its own repo, and added to other apps as a
  package.

## The order

1. **Harness:** a standalone app (in `tools/`, as the other probes are)
   with the ShowTools tree above and dummy content. Check:
   - dragging, closing to each edge, the handles, double-click;
   - popping a pane out as a panel and as a window, and putting it back
     in its slot;
   - remembered sizes and window positions across a relaunch;
   - window resize, and Restore Defaults;
   - no layout-loop exception under rapid changes.

   It's run on the Mac by the Claude Code there, and felt by Jason.
2. **ShowTools' main window** on PaneKit: the Library pane and the
   full-width timeline pane. `NavigationSplitView` goes.
3. **Edit Show's and Edit Slides' columns** on PaneKit: `ColumnsSplitView`
   and `VSplitView` go.
4. **ShowTools' panes popping out** (`spec/windows.md`): the library
   panel, the inspector panel, the Timeline window. PaneKit already does
   the moving by then; this step is the show session, so the panes have
   their state to take with them.

## Open questions (for Jason)

1. The name. PaneKit is a placeholder.
2. **Its own repo now, or later?** Starting inside ShowTools is quicker,
   and the target boundary keeps it clean for lifting out.
