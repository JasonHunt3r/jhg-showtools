# Item 17, start to (near) finish: the reorder schema through the drag itself

One continuous session, 2026-09-25, picking up "let's start on the reorder
schema migration" and ending mid-way through a second attempt at the
drag's own animation and feel. Superseded by `spec/status.md`'s Item 17
entry and `spec/plan.md`'s "Reordering" section for current state — this
is the story of how it got there, including the parts that didn't work.

**Read "What's actually broken" at the end first.** Everything in
between reads as a string of confirmed fixes — it wasn't. The drag
itself never actually worked, per Jason's real hands-on testing at the
very end of this session; every "confirmed with axtool" claim along the
way was synthetic testing that didn't agree with real use.

## The schema and the sort option (commits `1b66687`, `1cc440b`)

Migration 14: `sort_key REAL` on `collection_items` and `group_items`,
backfilled from `added_at` on upgrade so no library reorders just from
opening it. Deliberately kept separate from `added_at` from the start —
`MediaCollection`/`MediaGroup` grew a second field, `addedAt: [Int64:
Double]`, so Date Added could keep reading real join-timestamps once
`sort_key` became a thing the user drags around by hand.
`Library.setOrder(_:inCollection:)` / `setOrder(_:inGroup:)` renumber
`sort_key` as plain integers from a dropped-into array — no gap-based
scheme, a personal library's collections aren't big enough for a full
renumber to cost anything. The grid's Sort menu gained **Custom Order**,
hidden in the plain Library (no membership there to carry an order at
all). 310 core tests by the end of this piece, all passing, including a
version-13-library migration test and reorder/`addedAt`-independence
tests.

The drag gesture itself: `LibraryGridView.tile(_:)` got an `.onDrop`
alongside its existing `.onDrag`, computing the dropped-at array against
the collection's/group's **whole** membership (`all`), not the filtered/
searched `visible` list, and calling the new `AppModel.setOrder` wrappers
(mirroring `moveGroup`'s own undo-registration shape). One "Reorder" undo
step per drop.

## Live reflow (commit `2b96f9c`)

Jason's ask: "shows the tile where it would be if you release the
click." A `displayed` computed property — `visible` with the dragged
file(s) pulled out and reinserted before whichever tile `dropTargetID`
names — feeds the grid's `ForEach` instead of `visible` directly, with a
new `draggingIDs` state set the moment `.onDrag` fires. `.animation`
makes the shift visible rather than a jump. Applies to list mode for
free (same `LazyVGrid` at one column, not a separate view). Confirmed
with a *held* synthetic drag — `leftMouseDown`, dragged, holds 2s before
`leftMouseUp` — so a screenshot mid-hold could catch the preview, since
an instantaneous drag settles before a screenshot can be taken.

## Three bugs from Jason's own hands, one session

1. **General rapid back-and-forth swap, any drag.** Root cause: once a
   dragged tile's own live-reflowed position slid under the cursor, its
   `isTargeted` fired `true` for *itself* — `displayed` correctly refused
   to make a dragged tile its own target and fell back to the un-
   reflowed order, which put the real target back under the cursor,
   re-triggering `true` on it, reflowing again. A feedback loop on every
   drag near any tile. **Fixed** (commit `06f0aac`): a dragged tile can
   never set `dropTargetID` at all.
2. **The last tile not flowing.** Nothing could ever become the true
   last item — "insert before target" always left whatever was already
   last still last. **Fixed**: dropping on the actual last tile inserts
   *after* it instead, in both the preview and the commit.
3. **List view "not working."** Same fix as (1) — it's the same code,
   `ForEach(displayed)` at one column, not a separate implementation.

Also found, methodology note: reproducing (2) with fast synthetic drags
gave a genuinely separate, still-unsolved problem — see "What's still
actually broken," below.

## A real regression, self-inflicted, found and reverted same session

Tried switching `sort` to `.custom` **inside `.onDrag`**, at pickup, so
the live preview and the eventual commit would always agree on which
order they're working from. `sort` is `@AppStorage`, driving
`filtered`/`visible`/`displayed` — writing it synchronously inside
`.onDrag`'s own closure rebuilt the whole grid, including the tile the
drag was starting from, before AppKit had finished latching onto the
drag that closure was in the middle of starting. Every drag, in every
view, snapped straight back to its origin (Jason: "it is not reordering
the dragged item. In any view. It's just returning it to where it
was."). Reverted to switching in `reorderDrop`, on the actual drop —
commit `fd41b33`.

**Then a second correction, same evening.** Jason: reverting to
"switch on drop only" put back the exact thing he'd already asked
changed — not a safe fallback, a regression to a *known-wanted-fixed*
behavior. The actual fix wasn't "give up on early switching," it was
"stop trying to switch mid-gesture at all" and instead **explain** the
drop-time switch rather than leave it silent or try to make it earlier.
`CustomOrderNotice` (same `NSAlert` + `showsSuppressionButton`
convention as the existing `GroupToCollectionNotice`) shows once,
explaining that dragging switches the list to Custom Order, with a
"Don't show this again" checkbox — one button, no Cancel, since Jason
was explicit: "it shouldn't scold me to go do something else before
returning to do what I'm already instinctively doing." The reorder
always completes regardless of the alert. Also added the same session:
a separate header strip (`sortStatusBar`), below the search/filter/sort
toolbar, always showing the active sort by name — "which view is in
play" at a glance. Commit `9bccebe`. Confirmed with axtool: the alert's
wording, its persistence, its suppression, and the header strip tracking
live sort changes (including right after a drag switches it).

## What's actually broken (corrected after real hands-on use)

Everything above this point — the oscillation fix, the last-tile
insert-after, list mode, the Custom Order notice, the header strip — was
verified with synthetic axtool drags across this whole session and each
looked solid at the time. **Jason then tried it by hand: drag-and-drop
does not reorder the list at all, in any view, including Custom
Order.** Not a distance-dependent failure, not something that only
shows up several rows away — it just doesn't work, full stop.

This session's own diagnosis at the time — that a long-distance drag
specifically fails because per-tile `isTargeted` hit-testing is tied to
*where tiles are currently drawn*, and the reflow keeps moving that out
from under a traveling cursor — **is retracted, by Jason directly: "You
assumed a connection about drag length that doesn't exist… It's just a
bad hypothesis which isn't correct."** It was built entirely on
synthetic repro (a held-drag probe, screenshots mid-gesture) that
apparently doesn't represent what actually happens with a real hand on
the trackpad. Do not carry the geometry/`DropDelegate` idea forward as
if it were a confirmed diagnosis — it wasn't one.

**Jason's own proposed redesign**, to build fresh rather than debug the
existing `displayed`/`dropTargetID` mechanism further: on drag, the
destination slot becomes an **empty tile (or row, in list mode)** — a
gap — displacing the others around it. The empty spot itself is the
"here's where it lands" signal, rather than the current approach of
reordering the *other* tiles' identities into a preview arrangement.

**The lesson for next time:** synthetic axtool drags produced a long,
detailed, internally-consistent story across this whole session — held-
drag screenshots, precise coordinate math, repeated retries — and none
of it caught that the feature doesn't work at all for a real hand. A
"confirmed with axtool" claim about drag-and-drop specifically is not
evidence the feature works; only a real trackpad drag is.

## A testing-skill lesson, same session

`defaults import` (used to "restore" Jason's shared preferences after a
test copy) only overwrites keys the backup file already had — it does
**not** delete a key a test session's own build newly created.
`customOrderNoticeDismissed` (this session's new suppression flag)
stayed set in the shared domain after an import that predated the key's
existence. Now in `showtools-testing`: diff or explicitly `defaults
delete` anything a session's own new feature writes.
