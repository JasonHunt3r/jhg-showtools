# The crash hunt, session 2 — methods tried, and why the conclusions here are suspect (2026-09-23)

Jason reported the layout-loop crash (`2026-09-23-crash-hunt.md`) hitting
him live: switching Edit Show ↔ Edit Slides, with the outer columns
shoved off-window. This is that session's record — what was tried, in
order, and what each attempt actually showed. **Read this for the
methods, not the conclusions.** Partway through, Jason stopped the
session and said the conclusions below don't match what he's actually
seeing (a single click on the mode toggle crashes it for him, not
"mostly survives"). That contradiction is unresolved. Nothing here
should be treated as settled until it's checked against what he sees by
hand.

## Starting point

`~/Library/Logs/ShowTools-exception.log` had 14 raises in the hours
before he wrote in, the last one a few minutes before, timestamped
right when he said it crashed. Read with `tail`/`grep` — no tool needed
beyond the file itself. This is the same log and the same exception
`2026-09-23-crash-hunt.md` (session 1) already named:
`NSGenericException`, AppKit's layout-loop guard.

## Method 1: read the code around his repro

He said the crash came from switching modes. `ShowView.swift` showed
the mode switch (`EditMode`, an `@AppStorage` Picker) replaces
`EditSlidesView` (a plain `List`) with `EditShowView` on every toggle.
`EditShowView` builds `ShowColumns`, an `NSViewRepresentable`, whose
`makeNSView` constructs a fresh `ColumnsSplitView` (a hand-rolled
`NSSplitView`) from scratch every time it mounts. First theory: a fresh
`NSSplitView` build is a "first layout" event, same shape as the
launch-time crash. **This theory did not survive contact with the
actual exception stack** (see Method 3) — `ColumnsSplitView` uses none
of the SwiftUI machinery the crash's stack trace names. Recorded so
it isn't retried.

## Method 2: build, and full test suite, after each code change

Every code attempt below went through the same loop: `swift build` →
`swift test` (267 core + 12 BGTools, all passing throughout — the bug
is a runtime AppKit/SwiftUI interaction, not caught by any unit test)
→ `./make-app.sh` → hands-on check. This loop is sound and is the
right one to keep using.

## Method 3: read the exception log's full stack, not just its reason string

The reason string ("more Update Constraints passes than views") is the
same for every entry and says nothing about *which* column. The
**stack trace frames** are what differ, and reading the full 60-80 line
stack of specific entries (not just `grep reason:`) surfaced the actual
useful fact: frame 27 (or 21, depending on the entry) is
`SwiftUI.SplitViewChildController.hostingView(_:didUpdateMinSize:
maxSize:)`. That symbol belongs to SwiftUI's own split-column code —
`NavigationSplitView` columns and the `.inspector()` column — not to
any hand-rolled `NSSplitView`. This is the one finding from tonight
that rests on something more solid than a trial count: a symbol name in
a crash stack, not a timing measurement.

**Method for finding it:** `grep -n "^20" log` to list entry
timestamps, then `sed -n '<line>,<line+80>p' log` to read one entry's
full stack (the reason line alone was read first every time, by habit —
worth remembering to read past it).

## Method 4: axtool — driving the app by hand from the command line

`tools/axtool.swift`, built once with `swiftc`, gives `find` (locate a
labelled element and its click point), `click`, `front` (raise the app
before clicking — events go to whatever's frontmost), and `dump`
(accessibility tree). Used throughout to click the Edit Show/Edit
Slides segmented control and the sidebar's show row without a person's
hands. **This substitutes for a mouse, not for judgement about pacing**
— see Method 7.

## Method 5: `pgrep` + `tools/list-windows.swift`, not `pgrep` alone

`pgrep` reports the process is alive even when it's showing a "did you
mean to reopen" alert with no real window — the same trap
`2026-09-23-crash-hunt.md` already named from session 1's earlier
mistake. `list-windows` (built once with `swiftc`) was used every time
to confirm an actual window, not just a process.

## Method 6: three code-level fix attempts, each built, tested against a repro, and reverted

1. **Move `ShowView`'s `.inspector()` modifier** so it mounts only with
   `EditSlidesView`, instead of `.inspector(isPresented: mode == .slides
   ? $inspectorShown : .constant(false))` toggling in the same
   transaction as the whole mode swap. Reasoning: the crash names the
   inspector's own column controller, so stop forcing its presented
   state to flip in lockstep with a content-type change elsewhere.
   Built, tested (15-toggle and later 20-toggle automated stress: click
   Edit Show, wait, click Edit Slides, wait, repeat), **crashed again
   with the identical stack**. Kept in the tree anyway (`c03032b`) — it
   is a real simplification on its own regardless of the bug, and did
   no measurable harm.
2. **`.frame(minWidth: 920)` on `MainView`'s `detail:` content.**
   Reasoning: if the detail column's *reported minimum size* changes
   when its content swaps type (grid vs. list vs. `ColumnsSplitView`
   tree), pin it so it can't. Built, tested against the 20-toggle
   stress repro, **crashed again, identical stack.** Reverted.
3. **`.navigationSplitViewColumnWidth(min: 920, ideal: 920)`** in place
   of the `.frame` version — the modifier `NavigationSplitView` actually
   reads for a column's constraints, rather than a generic `.frame`
   hint. **This one made it worse**: the app crashed on the very first
   show selection, before any stress test, where the unmodified build
   hadn't. Reverted immediately; flagged in `status.md` as tried and
   worse, so it isn't retried without a real theory for why.
4. **`.transaction { $0.disablesAnimations = true }`** around the
   `detail:` switch. Reasoning: an implicit crossfade/resize between
   two very differently-shaped views might be the thing computing a
   new min/max size mid-animation, mid-layout-pass. Tested against a
   6-trial "launch, click a show" repro: **6/6 crashed, unchanged.**
   Reverted.

   All three are confirmed absent from the tree — `git diff` was run
   after each revert, and `git log` shows only #1 landed
   (`c03032b`, plus two doc-only commits: `eca46f2`, `f49ef71`,
   `d7ce408`).

## Method 7: repro counting — and where it went wrong

This is the part Jason interrupted the session over, and it deserves
the most scrutiny.

- A batch of "fresh launch, then select a show" trials came back 9/9
  crashed, across three different builds, which read as a solid,
  non-bursty repro — a big claimed upgrade over session 1's "bursts are
  real, no trial count means anything."
- That 9/9 turned out to trace to **this session's own repeated
  incremental Xcode rebuilds**: `swift build` + `./make-app.sh` run
  many times in a row, without ever clearing `build/xcode`'s derived
  data, between fix attempts. A **fully clean rebuild**
  (`rm -rf build/xcode build/ShowTools.app` before `./make-app.sh`)
  survived the *identical* repro **5/5**.
- Then, on that same clean build, the identical "settled launch, click
  a show" sequence, repeated once more at an ordinary pace, **crashed**.
- So: not a stale-binary artifact (that theory doesn't survive the last
  point either), and not a clean, repeatable 9/9 signal. Both claims
  made confidently within the same session, in sequence, on the same
  question, contradicted each other. **Neither is trustworthy as
  stated.**

**What this means for method, not just for this bug:** a small number
of automated trials, run by a script that controls pacing precisely
(0.4s between clicks, or a `.task` firing on the next run-loop tick),
is not the same experiment as a person clicking once, and both were
called "the repro" in the same session without that distinction held
onto. Jason's report — a single click, reliably, for him — is a third
data point that doesn't match either automated result. It was not
chased down before the session was stopped.

## Housekeeping done correctly

- `defaults read com.jhg.showtools runningTestLaunches` checked and
  cleared after every crashed test copy, per the testing skill.
- Jason's real preferences (`editMode`, the sidebar's
  `NSSplitView Subview Frames` key) drifted at least twice from test
  copies sharing his prefs domain, and were diffed against a
  `defaults export` backup and restored each time. Confirmed restored
  at the end of the session.
- `~/Applications/ShowTools.app` (his real, installed copy) was **read
  from but never overwritten** — its build date and the commit it
  corresponds to (`8db7ffc`/`a0be113`, 01:38) were checked, and it was
  launched once against a scratch library (never his real one) to
  compare against `build/ShowTools.app`.
- One `kill -9` (instead of plain `kill`) on a crashed test copy left
  a stale `runningTestLaunches` note that then refused three
  subsequent launches, wasting a chunk of the session before it was
  recognised as self-inflicted rather than a real crash. Worth
  remembering: **`kill -9`'s cost lands on the next launch, and it
  looks exactly like the real bug** until you check the note.

## What's actually still true

Only what doesn't depend on a trial count:

- The exception is AppKit's layout-loop guard, always the same reason
  string.
- The fatal stack, read in full, names `SplitViewChildController` —
  SwiftUI's own split-column controller, not `ColumnsSplitView`.
- Three specific code changes were tried and didn't stop it; one of
  them made a specific symptom (crash on first show selection) worse.
- The bug's reported frequency is sensitive to how the trial was run
  (automated pacing, script-triggered selection, incremental vs. clean
  builds) in ways this session did not fully control for, and at least
  one of tonight's own confident claims about frequency was wrong.

Everything else in `spec/status.md`'s Known Issues entry that traces to
tonight should be read with that last point in mind until it's checked
against Jason's own hands, not another automated run.
