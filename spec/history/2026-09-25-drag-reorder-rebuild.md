# Item 17, rebuilt: the gap, the pile, and edge scrolling

The session after `2026-09-25-drag-reorder-session.md`, same day (evening),
picking up "drag-to-reorder doesn't actually work". It ended with the
feature working by Jason's own hand, and with the stack effect's terms and
dials written down in `spec/plan.md`, "Reordering" — read that for the
current design. This is how it got there, wrong turns included.

## What was actually wrong

**Half of "doesn't work at all" was the plain Library.** Jason's window
was on the plain Library, where a drag is refused by design (no order to
save) — silently, with the sort strip reading "Custom Order". Jason: "I
must have been dragging in the library thinking it was the collection."
Fixed as a side effect of the rebuild: a drag there now says why.

**My first theory was wrong, and a test showed it before any code was
written.** I read the code and predicted the preview put the dragged tile
under the pointer, so every drop landed on it and did nothing. Three slow
synthetic drags on Jason's own copy (his go-ahead) all reordered
correctly. Stopped and asked instead of building on it.

**The real defect showed up only when watched.** Jason asked whether I'd
seen "everything jumping around back and forth". I hadn't looked — every
check so far read the result, never the screen during a drag. 45
screenshots of one slow drag showed it: tiles sliding over and back
repeatedly, the target ring blinking, and the drop saving the **wrong
order** (3,2,1 expected, 1,2,3 saved). Cause: each tile reported "the
pointer is over me", that report moved the tiles, the tile slid out from
under the pointer, the preview cancelled, and around again. The previous
session's fix (a dragged tile can't be the target) only removed one leg
of the loop.

## The rebuild (commits `d3b25a2`, `2260e51`)

Jason's design from the previous session — the destination becomes an
empty slot — built with one drop handler over the whole grid working out
the slot from the pointer's position and the grid's geometry
(`Reorder.slot`), so the tiles moving can't change the answer. A drop
saves what's on screen (`Reorder.merge`; Jason chose "what I see" from
another sort, and hidden files keep their places). Same 45-frame capture
afterwards: one-way shifts, correct order. Then Jason by hand: "boom!
that's the ticket."

## Undo that never reached the menu (commit `16f661a`)

Edit ▸ Undo stayed disabled after a reorder. Measured with notification
probes rather than guessed: the undo step *was* registered, on the right
manager, but it was registered outside any event (just after the drop),
so it sat in AppKit's automatic group, which stays open until the next
event — no close, no checkpoint, for 3s idle. `UndoMenuState` never
refreshed; the first ⌘Z only closed the group, the second undid. A
scratch program then showed an explicit group nests inside the automatic
one and posts only DidCloseUndoGroup after the action. Fix: the drop
opens and closes its own group, and `UndoMenuState` also listens for
DidCloseUndoGroup. One of my own tests along the way was invalid (a
sideways drag in list mode, which drops a file back into its own slot).

## Several files: from AppKit's stack to our own pile

Jason's item 5: dragging a selection showed only the grabbed file. A
standalone harness proved AppKit's multi-item drag ("flocking") could be
started from a SwiftUI tile and still reach SwiftUI's drop handler. Built
it; Jason: "kind of hectic, and in the list view it doesn't work well at
all. No rotation, just bring together into a tidy, slightly overlapped
stack."

The harness again: `.none` formation, then re-asserting `.none` on every
move — the pictures still tilted. The tilt is built into multi-item drags.
So the drag became one item carrying one picture we draw (the pile), with
the fly-in drawn by the grid. Jason, mid-build: "the bigger the stack, the
smaller the offset? or if more than X, then just use a stack of 5 … just
visually represent a stack" — both went in. Found and fixed on the way:
see-through list cards muddled the pile; a shrink-on-landing pulled
full-width list rows sideways; AppKit's own end-of-drag animation doubled
the landing (the drop now blanks the drag picture).

## Edge scrolling

Jason: the grid "doesn't jog the window pane at the edges; the list view
does". Every synthetic test scrolled fine — held still, multi-file, timeline
open, both directions. My guess (the pile hangs far below the pointer in
grid mode, and AppKit's zone is a thin strip at the pointer) matched
Jason's own read: "the drag objects are large and the trigger space is
narrow… it's fussy, not intuitively smooth." Built our own: a zone sized
from the pile's overhang, a timer so a still pointer keeps scrolling, the
gap following the scroll.

Then Jason, with 186 files in the test collection: the speed should ramp
toward the edge, and — having noticed macOS shrinks the pile over the
header or a closed pane — "as you get closer, the stack live shrinks
until it is the same size as the handful". Measured the handful (a 363pt
grid pile → ~121pt wide; a 320×34 list card → ~199×20: both "fit in
about 200×130"), and put the speed (cubed) and the shrink on one ramp.
Staged, still-pointer drags confirmed: no scroll mid-grid, a crawl at the
zone's start, fast at the edge, the pile ~270 → ~250 → ~185 → ~135pt.
Jason: good enough to close.

## Found along the way, not fixed

- **`LibraryLocation.isInICloud` loops forever on a path with `..`**
  (`Library.swift:50`): my own bad launch path (`…/Library.sqlite/..`)
  hung a test copy at 100% CPU before any window. It needed `kill -9`
  and the launch note cleared by hand. A real latent bug.
- **The sort strip reads "Custom Order" in the plain Library.** Deferred
  by Jason.
- **Any undo registered outside an event, elsewhere in the app, has the
  same invisible-until-next-event behaviour**; `UndoMenuState` now
  catches a group closing, but a bare registration outside an event
  still posts nothing until then. Only the reorder was checked.

## Method notes

- **Watch the screen during a drag, not just the result.** The 45-frame
  capture (`screencapture -R` in a loop while a slow drag runs) found in
  one run what result-only checks missed all afternoon.
- **A slow synthetic drag is a fair stand-in here; a fast one isn't.**
  `axtool drag` posts its moves back to back; a 25 ms-per-step drag
  reproduced the loop Jason saw by hand.
- **The drag tools refuse unless ShowTools is frontmost** — needed: the
  test copy sat exactly over Jason's window, and his editor overlapped it.
- **zsh doesn't split `$var` into words**: a `set -- $pair` loop silently
  took no screenshots. Use arrays.
