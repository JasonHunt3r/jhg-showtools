# Edit Slides' inspector: off SwiftUI's `.inspector()`, onto `ColumnsSplitView`

**Status:** Built 2026-09-23. `ColumnsSplitView` got the two-pane shape
(option 1, §"Two ways to close that gap"), `ShowColumns.swift` got
`TwoColumns` for it, and `ShowView`'s `.slides` case uses it in place of
`.inspector()`. Verified with the exact repro from the crash hunt: 32
toggles against a copy of the real library, zero new exceptions. **Left:**
nothing from this plan — see "What this doesn't cover" below for the two
unrelated issues found alongside it.

## Why

The layout-loop crash in "Known issues" (`spec/status.md`) is caused by
SwiftUI's `.inspector()` modifier on Edit Slides. Confirmed tonight
(`spec/history/2026-09-23-crash-hunt-session3.md`): stripping
`.inspector()` out of `ShowView`'s `.slides` case survived the exact repro
that crashed every other build tried — selecting a show, and 16 rapid
Edit Slides/Edit Show toggles at 0.4s pacing, against a copy of Jason's
real library. Every other theory tried tonight (the Ken Burns rename,
one show's data, persisted window/split state, which git commit) changed
nothing; only this did.

`EditShowView` already solves the same problem — showing an inspector
panel beside a list — without SwiftUI's `.inspector()` at all. It lays
its own inspector out by hand, through `ColumnsSplitView` (a hand-rolled
`NSSplitView`, `ColumnsSplitView.swift`), and it has never appeared in
any crash stack tonight or in the two prior crash-hunt sessions. The job
here is to put Edit Slides on that same, already-proven mechanism —
**not** to write a second, differently-shaped hand-rolled split view.

## What's actually reusable, and what isn't

`ColumnsSplitView` is currently hardcoded to exactly three roles —
`main` (absorbs window resizing, has a hard minimum), `list` (a
resizable middle column), `inspector` (collapsible, draggable open from
the edge) — addressed positionally (`subviews[0]`, `subviews[1]`,
`subviews[2]`) throughout the class (`arrange()`, the delegate's min/max
coordinate rules, the collapse/reveal logic).

Edit Slides doesn't have a `main` preview column — it has one primary
column (`DefaultsBar` + the slide `List`) and an inspector. That's the
`main` + `inspector` shape with no middle `list` at all, which the
current class can't express without a fake, invisible middle pane.

**Two ways to close that gap — pick the smaller one first:**

1. **Add a two-pane initializer** (`init(main:inspector:defaultsKey:)`)
   that skips the middle column: `listWidth` becomes 0 and unused,
   `arrange()` and the delegate rules drop their `list`-column branches
   when there isn't one. Smaller change, keeps today's three-pane
   behavior for Edit Show untouched.
2. **Generalize to an arbitrary column list** with a per-column role
   (resizes-with-window / fixed-range / collapsible), addressed by role
   instead of index. More reusable if a third shape ever shows up, but
   a bigger rewrite of a class that's already been hand-tuned against
   several measured AppKit quirks (see its own header comment).

Start with (1). Don't reach for (2) unless a third caller actually needs
it — CLAUDE.md's own rule against designing for hypothetical requirements
applies here as much as anywhere.

## Steps

1. **Extend `ColumnsSplitView`** with the two-pane shape (option 1
   above). Every place that indexes `subviews[1]` for `list` needs a
   guard for "no list column" — read the whole class first
   (`Sources/ShowToolsApp/ColumnsSplitView.swift`), it's dense and
   already carries hard-won fixes (divider grab width, collapse-by-drag,
   the `dividerColor` override, `shouldAdjustSizeOfSubview`) that are
   easy to break by accident.
2. **Give `EditSlidesView` its own `ShowColumns`-shaped wrapper**, or
   extend `ShowColumns` (`ShowColumns.swift`) to accept the two-pane
   case, wrapping `DefaultsBar` + the slide `List` as `main` and
   `SlideInspector` as `inspector`, each in a `ColumnHost` exactly as
   `ShowColumns.makeNSView` already does for Edit Show.
3. **Wire it into `ShowView`'s `.slides` case** in place of today's
   `.inspector(isPresented:) { SlideInspector(...) }`. Keep:
   - the toolbar Inspector button (⌥⌘I) and `inspectorShown` binding —
     call `setInspectorShown` the way `EditShowView` does;
   - double-click-to-open (`primaryAction` in `EditSlidesView.list`);
   - `SlideInspector`'s `close:` parameter — `EditShowView` already
     passes one; do the same rather than inventing a second close
     mechanism.
   **Do not** re-add `.inspector()` or `.inspectorColumnWidth()`
   anywhere in this code path — that's the actual trigger.
4. **Test.** `swift build`, `swift test` (regression baseline — none of
   this should touch existing behavior). Then rebuild the app
   (`rm -rf build/xcode build/ShowTools.app && ./make-app.sh` — a clean
   rebuild, not incremental; an incremental one produced a false "10/10
   clean" reading in an earlier session) and run the exact repro from
   tonight: a **copy** of `~/Pictures/ShowTools Library.noindex` (never
   the real one — `showtools-testing` skill), select "Trucks to the
   Future," then Edit Slides ↔ Edit Show at least 16 times at ~0.4s
   pacing. Confirm zero new entries in
   `~/Library/Logs/ShowTools-exception.log` (count before and after,
   don't just watch for a visible crash — the exception fires far more
   often than it kills the process).
   Also confirm, by hand or with `axtool`, that the ported inspector
   still: opens/closes from the toolbar and by double-click, shows the
   right slide's settings, and its divider drags/collapses/reveals the
   way `ColumnsSplitView`'s existing behavior already does in Edit Show.
5. **Update `spec/status.md`'s Known Issues entry** in the same commit
   that lands the fix — say what was true, what changed, and point at
   this file and the two crash-hunt history docs rather than repeating
   them.

## What this doesn't cover

- `EditShowColumns`' own saved-frame autosave data was found
  inconsistent tonight (`spec/history/2026-09-23-crash-hunt-session3.md`)
  — three panes with overlapping x-ranges. Unrelated to this crash (Edit
  Show was never in play in any repro tonight) but worth a look
  separately.
- "Shorty"'s leftover `kenBurns`-keyed slide setting (silently reset to
  off by the current app, which only reads `panAndZoom`) is real data
  loss, also found tonight, also unrelated to this crash. `CLAUDE.md`
  already documents the general risk (renamed/removed enum cases and
  keys reset silently); this is one concrete instance of it, still
  sitting in Jason's real library.
- This fix is scoped to Edit Slides' inspector, the one confirmed
  trigger. It's not proven that no other `.inspector()`/
  `NavigationSplitView` combination in the app can hit the same AppKit
  bug — none of tonight's tests found the *outer* sidebar
  `NavigationSplitView` unsafe on its own (Edit Slides without any
  inspector survived show selection and mode toggling fine), so the
  inspector column specifically looks load-bearing for the bug, not
  `NavigationSplitView` in general. Still worth keeping an eye out.
