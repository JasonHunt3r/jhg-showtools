---
name: showtools-gotchas
description: Traps in this codebase found by measurement — AVFoundation failing quietly, measuring the right quantity, @ObservationIgnored on PlaybackEngine.show, undo restoring whole-show snapshots, the older-version test trap, synthetic events not being proof, per-window undo managers, AppKit layout that measures during layout. Load before debugging unexpected behaviour or touching export, playback, undo or migrations.
---

# Traps, each found by measuring

Every one of these looked like working code, or like a different bug.
None announced itself as an error.

## AVFoundation fails quietly

Everything that went wrong in video export looked like a hang or a
plausible picture, never an error: an untagged colour matrix, two
different two-input writer deadlocks, a non-interleaved ASBD, a frame
decoded early and thrown away. Each was found with a probe or a
measurement, **none by re-reading the code**.

- **Tag the colours.** Untagged, encoder and reader disagree about the
  YCbCr matrix: green went in at 0.1 and came back at **0.016**, on every
  codec including ProRes. `AVVideoColorProperties` set to Rec. 709 fixes
  it. A `CIColor` rendered straight to a pixel buffer round-trips exactly,
  which is what placed the fault in the encode rather than the Compositor.
- **A writer with two inputs deadlocks two ways**, both silent hangs.
  (1) Mark a track finished the moment its last sample lands — an
  unfinished track hangs the other behind it. (2) **Preferring the track
  that is behind is not waiting for it**: an input that isn't ready is
  usually waiting on the *other* track before it can flush. Spinning on
  the one behind hung the picture at frame 38 of 60 with the sound input
  sitting ready and unasked. **Feed whichever input will take data.**
- **Interleave audio by hand** for a writer: a non-interleaved ASBD's
  `mBytesPerFrame` counts one channel, so the writer reads a fraction of
  each block.
- **Don't discard a frame decoded before its moment.** One stashed and
  then overwritten by the next decode lost every frame beginning just
  before the time asked for, so any time just past a frame boundary
  returned the previous frame.
- **Resolve file URLs before leaving the main actor.** Swift 6 caught the
  writing task capturing the SQLite-backed `Library`; it now gets a plain
  `[Int64: URL]`.
- **Write off the main thread.** `MoviePictureTrack.write` blocks.

## Measure the right quantity

An **equal-power crossfade holds RMS, not peak** (two tones at 0.707 sum
to a peak of up to 1.41, so a correct crossfade read as a peak looks like
clipping), and **a peak over a window reports its loudest moment, not its
middle**, so over a fade it reads the window's louder edge.

Both made correct code look broken, and **both caught me a second time
after I had written the first one down.** Expected levels come from
`AudioClip.gain` over the same window, not by hand.

## Extract a rule rather than reimplement it

A video slide **held longer than its video plays it again from
`clipStart`** rather than freezing, and the line is 0.1 s (held 4.5 s, a
4 s video loops). That rule lived in the player and an exporter would
never have guessed it. `VideoSlideTiming` now holds it for both — asked by
`VideoSlot` and the exporter alike.

## SwiftUI and AppKit

- **`PlaybackEngine.show` is `@ObservationIgnored`.** A view that reads it
  doesn't redraw when the show changes, so read the saved `show` that
  SwiftUI observes. The preview's image bar read the engine's copy and
  went stale — a bug that only showed once a second control could change
  opacity.
- **The Edit Slides defaults bar is two unconditional rows** rather than
  `ViewThatFits`, and the reason is arithmetic, not a bug: the row needs
  ~1490pt on one line and the window's own minimum is 1100, so one line
  can never fit at any window size and there is nothing to choose. Don't
  "restore" `ViewThatFits` there.
  **It was not removed because it caused the launch crash, and nothing
  should be read into its removal.** The reports clear it outright — the
  first crash predates it being added, and six builds across five
  sessions crashed. Dropping it was housekeeping on a view that had no
  decision to make, done while that area was under suspicion. Treating it
  as a lead is a snipe hunt; `spec/history/2026-09-23-crash-hunt.md` says
  what the evidence does and does not support.
- **Modifiers on a `Group` apply to every child.** Use a `ZStack` when a
  container needs its own onAppear/onDisappear/task.
- **A separate window's `\.undoManager` isn't the presenting window's**,
  and the *key* window's own `undoManager` is what ⌘Z asks. Full write-up
  in `spec/macos_panels_guide.md` (in `jhg-cutcheck`).
- **In a `List`, rows drag with `.itemProvider`, never `.onDrag`.**
  `.onDrag` turns a click on the row's content into drag tracking, so the
  row won't select or double-click (only its empty edges do), and a drag
  carries one row, not the selection. The Library grid isn't a List, and
  its tiles' `.onDrag` is fine.
- **SwiftUI hosting views hit-test all their content, clipped or not.**
  Edit Show's columns use `ColumnHost`, which takes the mouse only inside
  its frame — or content wider than its column steals the next column's
  clicks and scrolling.
- **Harnesses first for AppKit questions.**

## Data that disappears quietly

- **Undo restores a whole-show snapshot.** Anything that lives in `Show`
  but shouldn't be undone (the editing state) has to be carried over
  explicitly when undoing, as `AppModel.update` now does.
- **Every model type saved as JSON decodes field by field**, never
  synthesized `Codable`: one unreadable field would reset all of them, and
  the next save would make the loss permanent.
- **Renaming a property renames its JSON key** where `CodingKeys` is
  synthesized — the saved value then reads as absent, and the next save
  makes that permanent. Pin the old string with an explicit `CodingKeys`.
- **Removing or renaming an enum case is the same trap.** An unreadable
  enum field falls back to its default, but `Transition` requires its
  `style`, so saved transitions of a removed style become the show's
  default, permanently, on the next save.
- **A new column breaks the older-version tests.** Each "a version-N
  library upgrades" test fakes an old library by dropping columns, so
  every newer column must be dropped too (the tests chain `DROP COLUMN`s).

## Proof

- **Synthetic clicks and key events aren't proof** of a bug, or of a fix.
  Settle a disagreement with a harness or, failing that, one real
  keypress or click from Jason.
- **Test the tests.** A new test should be run against the old code first,
  and fail there.
- **Measure with probes**, written to a file. `log show` returns nothing
  from this app in Claude's sandbox.
- **`pgrep` is not "the app is running"** — see the `showtools-testing`
  skill. Measuring aliveness that way invalidated an entire crash hunt.
- **Bursts are real.** Restore Default Layout provoked the crash seven
  times out of seven, then zero out of five on the next build with no
  relevant change. Never conclude anything from a run of trials; count
  exception-log entries over a long session.
