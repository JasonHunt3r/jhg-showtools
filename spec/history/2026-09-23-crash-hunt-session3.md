# The crash hunt, session 3 — the cause found, two false leads closed (2026-09-23)

Jason reported the layout-loop crash live: in Edit Slides mode, clicking
the header's mode toggle to switch to Edit Show killed the app. This
session found the actual cause. It also includes two significant
methodology failures worth reading past the result for.

## Methodology failures, first — read this before trusting anything below

This session asserted a firm, wrong timeline twice before Jason corrected
it, and he had to say so more than once before the digging actually
changed. Worth naming plainly:

1. **Read the exception log and git log, then stated a confident
   narrative** ("the crash predates the Ken Burns rename, so it can't be
   related") **from timestamps alone**, without checking it against what
   Jason actually remembered doing. He had a detailed, specific memory
   (a working session, an export, a close-and-reopen sequence across two
   different post-rename builds) that the timestamp-only reading missed
   entirely. Corrected after he said, in his words, to "ask questions
   more" instead of asserting.
2. **Assumed a synthetic-click test result generalized**, more than
   once, without checking the alternative explanation Jason offered
   (persisted preferences state carrying across every test launch,
   regardless of which git commit was built). That one turned out to be
   wrong too, but it was wrong for a reason worth having actually
   checked, not assumed — see "Ruled out" below.

**The fix going forward:** when the person who uses the app daily says a
timeline doesn't match what they experienced, that's better evidence
than a log reading, and the right move is to ask what they remember
before building another theory on top of the log.

## Method: a new probe, and how it was tested

`Sources/ShowToolsApp/LayoutLoopProbe.swift` (new tonight) swizzles
`-[NSView setNeedsUpdateConstraints:]` and keeps a ring buffer of the
last ~80 calls — each entry's dynamic class name (which, for an
`NSHostingView<Content>`, encodes `Content`'s type and so names the
actual SwiftUI subtree involved, not just "NSHostingView") and frame.
`ExceptionProbe` (existing) now appends that buffer to its log entry.
This is what let tonight's session see *which* columns were fighting,
not just that AppKit's layout-loop guard fired.

Every test tonight ran against a **copy** of `~/Pictures/ShowTools
Library.noindex`, never the real one, per the `showtools-testing` skill.
Preferences-domain hygiene (backup before, diff after, clear
`runningTestLaunches` after every crashed test copy) was checked
repeatedly and confirmed clean at the end — `defaults export` before and
after this session, byte-identical.

## Ruled out, each with a real test, not a guess

- **The Ken Burns → Pan and Zoom rename.** Built and ran the commit
  right before it (`5d10713`, code still says "Ken Burns" everywhere).
  Crashed identically, same exception, on the same repro. The rename
  landed at 01:38, over three hours after `ExceptionProbe` was written
  specifically because the app had already aborted 25 times that
  evening — the bug predates the rename.
- **One show's data.** "Trucks to the Future" has zero `kenBurns` keys
  anywhere (fully migrated). "Shorty" still has one (`slide 9`, plus its
  show defaults) — a real, separate bug: the current app silently drops
  that leftover setting on load (matches the risk `CLAUDE.md` already
  documents for renamed JSON keys). Both shows crashed identically on
  selection. The leftover key isn't the trigger.
- **Persisted window/split-view state.** Every test tonight, across every
  commit tried, read the same saved `NSSplitView`/window-frame state from
  the shared `com.jhg.showtools` preferences domain (it never resets
  between launches). Jason's alternative theory — that *this*, not the
  code, was what had changed — was tested directly: moved
  `~/Library/Preferences/com.jhg.showtools.plist` aside, `killall
  cfprefsd`, launched genuinely first-run (confirmed: `defaults read
  com.jhg.showtools` → domain not found). Crashed anyway, same
  exception. Preferences restored immediately after (verified
  byte-identical to the pre-session backup). Not the cause either.

## Found: `.inspector()` is the trigger

`ShowView`'s `.slides` case attaches SwiftUI's `.inspector()` modifier to
show `SlideInspector`. Every crash stack tonight named SwiftUI's own
split-column machinery (`SplitViewChildController`, `InspectorStyleContext`)
— the same finding session 2 had from stack traces alone, now backed by
the probe's captured sizes: the detail column and the inspector column
kept reporting *different* sizes to each other across consecutive layout
passes (detail width bouncing 1493 → 1235.5 → 978 → 1493; inspector
height bouncing 10 → 52 → 181), never converging.

Test: temporarily stripped `.inspector()` out of `ShowView`'s `.slides`
case entirely (no replacement UI — this was a test, not a fix; the code
change was reverted after). Rebuilt clean, ran the identical repro —
select "Trucks to the Future," then 16 rapid Edit Slides ↔ Edit Show
toggles at 0.4s pacing (the exact pacing that broke all three of session
2's fix attempts) — against a fresh copy of the real library. Survived.
Zero new exception-log entries. This is the first thing tried across
three sessions that has actually changed the outcome.

**Also found, independently:** an identical bug report,
`detlefs/Folder-Crest` issue #6 on GitHub — same exception, same
trigger shape (`NSHostingView` inside `NavigationSplitView`), same OS
build (`macOS 27.0, 26A428` — matches this Mac's `sw_vers` exactly),
app-level causes ruled out the same way, reported to Apple as an
AppKit/SwiftUI regression. Consistent with everything above: every frame
in the fatal stack that isn't one of tonight's own probes is inside
`AppKit.framework` or `SwiftUICore`/`SwiftUI.framework`, never ShowTools'
own linked code.

## What's next

`spec/edit-slides-inspector-port.md` — port Edit Slides' inspector onto
the same hand-rolled, non-SwiftUI-`.inspector()` mechanism `EditShowView`
already uses (`ColumnsSplitView`), rather than just leaving Edit Slides
without one. That file has the concrete plan.

## Loose ends found along the way, not yet acted on

- `EditShowColumns`' saved split-view frames (a *different* autosave key,
  Edit Show's own hand-rolled split) are internally inconsistent right
  now — three panes with overlapping x-ranges. Unrelated to this crash
  (Edit Show was never exercised in any repro tonight), but worth
  reproducing and fixing separately.
- "Shorty"'s leftover `kenBurns` key (above) means its saved Pan and Zoom
  setting is silently gone. Also unrelated to this crash, but it's real
  data loss sitting in Jason's actual library right now.
