# The crash hunt, looked back on (2026-09-24)

A debrief of the layout-loop crash (sessions 1–3, 2026-09-23), in
Jason's words and with hindsight, for the ops manual when it's written.
The technical record is in the three `2026-09-23-crash-hunt*.md` files;
this file is about **how the hunt went wrong, and what ended it.**

## What the crash was

AppKit's layout-loop guard (`NSGenericException` from
`-[NSWindow _postWindowNeedsUpdateConstraints]`) killed the app when a
show was selected or the mode switched. **Cause, confirmed in session 3:**
SwiftUI's `.inspector()` modifier on Edit Slides. Its column and the
detail column kept reporting different sizes to each other and never
settled. **Fix:** Edit Slides' inspector was ported onto
`ColumnsSplitView`, the hand-rolled split Edit Show already used
(`spec/edit-slides-inspector-port.md`).

## Jason's account (2026-09-24)

- **It was volunteered design.** Edit Slides' inspector was built without
  being asked for. Jason was surprised to find it existed at all. It was
  a good idea, but it didn't follow the established convention: Edit
  Show's almost identical collection list sat beside an inspector pane on
  `ColumnsSplitView`, and that one worked.
- **So it was never crash-tested when it went in.** It sat there, latent,
  through many later steps. It surfaced only when a particular action
  triggered it, long after it was built.
- **So the hunt went backwards from the wrong end.** It suspected the
  newest work, one change at a time: the Ken Burns → Pan and Zoom rename
  and the strip, the HEAD code, even clicking too fast (it measured how
  long a set of values took to load). None of those was the cause. The
  fast mode-switching was only ever the *repro*, the quickest way to
  trigger the crash for a test, never why it happened.
- **Up close, with no view of what was upstream.** "Claude got so focused
  on the problem that it failed to see that it lacked the understanding
  to solve it." It kept rewriting code to make the conflicting wrappers
  work, never considered that something upstream might be causing it,
  or that there's more than one way to skin a cat. It was close to giving
  up.
- **Conjecture got elevated to a vector.** Guesses were treated as
  findings and built on. One outlived the hunt: the belief that setting
  the sidebar raised the exception, written into `DefaultLayout.swift`
  and repeated as fact until Jason caught it on 2026-09-24.
- **What ended it:** Jason asked for *the cascade that leads to this*.
  The answer was that `.inspector()` couldn't sit inside that container,
  and he said: don't wrap it in that. Why does the same thing work fine
  "over here" for two days, and not in the later stuff?

## Was macOS 27 part of it?

**Jason's context:** the first version, with its inspector, was built on
macOS 26. He upgraded to macOS 27 for the new audio analysis (the beat
detection, which needs macOS 27). The inspector wasn't re-checked
across the upgrade. So `.inspector()` may have worked on 26 and broken
on 27.

**What points that way (not proven):**
- Session 3 found an identical report, `detlefs/Folder-Crest` issue #6:
  the same exception and trigger shape, on the same macOS 27 build as
  this Mac, reported to Apple as a regression.
- A web search (2026-09-24) finds other projects fixing the same thing on
  macOS 27. They describe the crash as the window being marked for layout
  again from inside its own layout pass, which macOS 27 now aborts:
  - [pomelohq/pomelo #104, "Fix editor layout-reentrancy crashes on macOS 27"](https://github.com/pomelohq/pomelo/pull/104)
  - [nickysemenza/macaudit #22, "Fix macOS 27 split-view crash"](https://github.com/nickysemenza/macaudit/pull/22)

**What cuts the other way:** inspector crashes were also reported on
macOS 26 ([Apple forums: "MacOs Tahoe inspector view crash"](https://developer.apple.com/forums/thread/801818)),
so it may have been fragile before 27 made it fatal.

**What would settle it:** the same build of the pre-port Edit Slides,
run on a macOS 26 machine or VM, with the same repro. Not worth doing
for its own sake, since the fix doesn't depend on the answer. It matters
only as a rule of thumb: **after an OS upgrade, re-check the SwiftUI
containers the app leans on.**

## The lessons

These are in `spec/how-we-design.md`, with the stories:
- The person using the app sees what the logs don't.
- Ask for the cascade before patching.
- When one thing works and its twin doesn't, the difference is the
  answer.
- Volunteered work follows the house pattern, and is announced.
- Stale knowledge is a guess too.

**Added by this debrief:**
- **A latent bug isn't in the latest change.** When a crash can't be
  pinned to the newest work, ask what was *never tested* rather than
  what was *most recently changed*.
- **A repro is not a cause.** The fastest way to trigger a bug says
  nothing about why it happens.
- **Knowing you don't understand is a finding.** When fixes keep
  failing, stop and say what isn't understood, and look upstream,
  instead of trying another rewrite.
