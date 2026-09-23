# ShowTools docs restructure — brief for Claude Code

Written 2026-09-23 in the Claude app, from a read of the public repo at
`a513e0d`. Jason has approved the layout below. **Start in plan mode:**
read this, read the files it names, then state your section-by-section
mapping back to Jason and wait for his go-ahead before moving anything.

## Why

The rules are fine; the *state* docs have drifted. `spec/handoff.md` has
grown to 773 lines of dated narrative in accretion order (Phase 4a before
4d before 4c; "Step 6" 140 lines above "Starting step 6"), with
contradictions (175 + 12 tests vs 267 + 12; 8 library items vs 13) and
Known issues that commits have already fixed. The feature specs were
written as plans and got "BUILT" appended step by step, but their opening
and closing paragraphs were never revised, so each one's first screen
describes the world before the work.

The cost is real: the rule that would have kept Jason's app from opening
to "Library problem" twice today lives at handoff line ~626, where no
session reads it before launching a test copy.

The organising principle (from the ClaudeCAM cleanup): **live docs hold
rules and current state; history holds events.** And from the Livery
Catalog restructure: **how-to and traps load on demand as skills**, so
CLAUDE.md stays short enough to be followed.

## Ground rules for this task

- **Docs only.** No code changes, no builds needed. If you find yourself
  wanting to fix something in the code, stop and list it separately.
- **Relocate, don't rewrite.** Narrative sections move with their wording
  intact — the exact phrasing of a measurement or a trap is the valuable
  part. Only two things get *written*: `spec/status.md` (new, present
  tense) and the status blocks on the feature specs. Corrections of stale
  claims (listed below) are edits, not rewrites.
- **Verify before correcting.** Every "this is stale" claim below came
  from reading docs and `git log`, not from running the app. Check each
  against the code or the commit before changing the doc; if one is wrong,
  say so and leave that line alone.
- **Keep feature specs where they are.** Source comments cite
  `spec/video-export.md`, `spec/video-audio.md` and `spec/bgtools.md` by
  path. Nothing under `Sources/` should need touching.
- **Commit per step**, per CLAUDE.md's rule (which is Jason's correction
  as of today — leave its wording as it is). Suggested commits at the end.

## Step 0 — find the conflicting rule (report only)

Jason has seen sessions sit on 11 uncommitted steps because of an old
"ask before committing" rule written for a different project. The
repo's CLAUDE.md now says the opposite, so if hesitation continues, the
old rule is probably loading from elsewhere. Look in
`~/.claude/CLAUDE.md`, any `CLAUDE.md` in parent directories of the
repo, `.claude/settings*.json`, and your own memory for this project.
**Quote any commit/ask-first/permission rule you find, with its path.
Don't edit it** — Jason decides. Same for anything in those places that
contradicts this repo's CLAUDE.md in other ways.

## Target layout

```
CLAUDE.md                        rules + layout + docs table
spec/plan.md                     decisions, phase by phase (as now)
spec/status.md                   NEW — state of play, present tense, ≤ ~150 lines
spec/bgtools.md                  feature specs, each opening with a status block
spec/video-export.md
spec/video-audio.md
spec/xcode-port.md
spec/first-run-brief.md          a brief for App Claude (not a build plan)
spec/history/                    NEW — dated events, never read for current rules
  README.md                      one line per file: what it is, what superseded it
  2026-09-21-audit.md            ← spec/audit-2026-09-21.md (git mv)
  2026-09-21-hands-on.md         ← spec/hands-on-2026-09-21.md (git mv)
  2026-09-22-alpha-test.md       ← spec/alpha-test.md (git mv)
  2026-09-2x-<topic>.md          ← handoff narrative, split by session/topic
  2026-09-23-crash-hunt.md       ← the full crash write-up
.claude/skills/
  showtools-testing/SKILL.md     NEW — how to test without touching Jason's app
  showtools-gotchas/SKILL.md     NEW — traps, found by measuring
```

`spec/handoff.md` ends up as either deleted (its content fully
relocated, `git log` keeps it) or a two-line pointer to `status.md` —
propose which.

## Mapping, file by file

### `spec/handoff.md` → five destinations

| Current section (approx. lines) | Goes to |
|---|---|
| "Since then (2026-09-23)" (8–29) | `status.md` — facts only: app installed from HEAD, real library healthy, demo media in it is his to keep or clear |
| "Start here", the day-five narrative of Xcode port, video-audio, video export and its traps (30–136) | `history/` — one file (e.g. `2026-09-22-day-five.md`). Its "What's left", "Test things still installed on Jason's Mac" and "Parked" (≈155–195) go to `status.md` |
| Phase 4a / 4d / 4c / 4b, Step 6, Phase 3b, Phase 3 as built, Starting step 6, Step 7 (196–605) | `history/`, split by session or phase as reads best, in **chronological** order |
| "Where it stands" table + schema paragraph (338–359) | `status.md`, near the top. Test count is **267 + 12** (verify with `swift test`, or count — do not trust either number in the doc) |
| "Still needs Jason's hands" (606–619) | `status.md` |
| "How to work on it" (621–652) | `showtools-testing` skill, except the four-line command block, which stays in `status.md` as "Quick start" |
| "Ask Jason later" (657–659) | `status.md` → Open questions. **Drop** the video-sound item: V1–V5 built it |
| "Known issues / debts" (661–749) | `status.md`, **current items only** (see below). The crash entry condenses to ~5 lines of current knowledge with a pointer; the full write-up moves to `history/2026-09-23-crash-hunt.md` |
| "Lessons (details in memory)" (751–773) | `showtools-gotchas` skill |

**Known issues to remove as fixed** (confirm each first):
- The "Style" label wrapping — fixed in `091792a`
- The Edit Slides header bar overflow — fixed in `091792a` (wraps via `ViewThatFits`)
- A video slide's end points half-clipped — fixed in `091792a`
- Inspector sliders have no live preview — fixed in `b66b4af`

**Known issues to re-examine, not delete:** the CPU note says "needs work
before Phase 5's desktop mode", but Phase 5 is built and B6 cut desktop
drawing ~20×. Reword to what's still true, or ask.

### `CLAUDE.md`

Keep Layout and Rules. Edits:

1. **Replace the opening paragraph** with a short docs table — each file,
   one line, marked *current*, *reference* or *history*. `status.md` is
   "read first each session"; `spec/history/` is "never read for current
   rules; only when a question is about why something is the way it is".
   Name the two skills and when they load.
2. **Add to Rules, in bold, beside "Never test against the real library":**
   a test copy shares Jason's preferences domain (`com.jhg.showtools`).
   A crashed test copy's `TestLaunchRecord` note makes **his** app refuse
   to open ("Library problem", empty window — it looks like a broken
   library); test copies also overwrite his column widths and window
   frames. After any test copy dies, check and clear
   `runningTestLaunches`; capture his layout keys before a test session
   and restore them after. (Source: handoff, commit `a513e0d`.)
3. **Correct the TestLaunchRecord sentence** in the first Rule. It
   currently says `kill -9` costs "one refused launch" as if that were
   harmless; the refused launch is Jason's.
4. **Delete** "(Until he has made a first real show there is nothing to
   disturb, so open and drive it freely on a scratch library.)" — his
   library now has Car Show, Shorty and Untitled Show.
5. "including the future video exporter" → the video exporter is built;
   make it present tense.
6. Add one line: the user-facing name is **Pan and Zoom**; the code and
   the setlist format still say `KenBurns` (settled `f0bd5d8`).
7. **Commit rule:** leave it word for word, and add one sentence — when
   a step closes an item in a feature spec, update that spec's status
   block in the same commit.
8. Move any how-to detail that is really testing procedure (the BGTools
   test-launch recipe, axtool usage) into the testing skill *only if*
   CLAUDE.md is still over ~150 lines after the above; otherwise leave it.

### Feature specs — add a status block, fix the stale lines

Status block, first thing under the title:

```
**Status:** Built 2026-09-22 (B1–B7). **Left:** Jason's hands-on pass;
the Pan and Zoom cost; telling BGTools when a library moves.
```

(Planned / Building / Built <date>; "Left: nothing" is a valid answer.)

- **`bgtools.md`** — line 5 says, in bold, "Nothing of BGTools is built
  yet." Remove it; the status block replaces it. The twelve open
  questions are all struck through as settled: propose folding them into
  Decisions (keeping the wording) or retitling the section "Settled".
- **`video-export.md`** — "Still open" leads with "Nobody has listened
  to an export yet." The alpha test (`077568f`) closed that; the commit
  touched `alpha-test.md` and `handoff.md` but not this file. Update.
- **`xcode-port.md`** — title says "(planned 2026-09-22)"; it's done.
  "Not part of this port" calls video export the plan's "Later"; it's
  built.
- **`video-audio.md`** — "Nothing to preserve: Jason hasn't built a real
  show yet… Check this still holds before building." Built, so moot — but
  the premise is now false. Add a dated note that real shows exist now,
  so any future change to the silent default has saved slides to respect.
- **`plan.md`** — Stack says "built with SwiftPM and wrapped into a
  `.app` by a shell script. No Xcode project." The Xcode port overturned
  that; update with a pointer to `xcode-port.md`. "Open questions: None"
  → point at `status.md`'s open questions (image stickiness is still
  open). Otherwise leave it: its BUILT tags are current.
- **`first-run-brief.md`** — "(later) live on each monitor's desktop":
  BGTools is built. This brief goes to App Claude, which has nothing else
  to correct it with, so check the rest of it for the same drift.

### New: `spec/status.md`

Present tense, rewritten (not appended) each session. Sections, in order:
Where it stands (the table) · What's next · Still needs Jason's hands ·
Open questions · Known issues · Test things installed on Jason's Mac ·
Quick start. No dated narrative — if it has a date and a story, it
belongs in `history/`. Target ≤ ~150 lines.

### New skills

```yaml
---
name: showtools-testing
description: How to launch, drive and measure ShowTools without touching Jason's real app, library or preferences — scratch libraries, the shared preferences-domain trap, axtool, window-not-pgrep checks, audio taps, seeding data with sqlite3, stcli render. Load before launching any test copy or doing a hands-on check.
---
```

```yaml
---
name: showtools-gotchas
description: Traps in this codebase found by measurement — AVFoundation failing quietly, measuring the right quantity, @ObservationIgnored on PlaybackEngine.show, undo restoring whole-show snapshots, the older-version test trap, synthetic events not being proof, per-window undo managers. Load before debugging unexpected behaviour or touching export, playback, undo or migrations.
---
```

The Lessons heading says "details in memory". If your memory holds
details for any of these, bring them into the skill so they're in the
repo, and say which ones you added.

## Also flag (don't act)

- A stray `Screenshot 2026-09-21 at 1.25.46 AM.png` is committed at the
  repo root. Ask Jason: delete, or move somewhere it's written up.

## Verification before the first commit

1. **Nothing dropped:** list every `##`/`###` section of the old
   `handoff.md` with its destination file. Every line lands somewhere or
   is named as deliberately removed (the four fixed issues, the video-sound
   "ask later").
2. `grep -rn "handoff\|audit-2026\|hands-on-2026\|alpha-test" .` (excluding
   `.git`) — fix every pointer to a moved file.
3. Line counts: CLAUDE.md, status.md, both skills.
4. `swift test` is not needed (docs only), but do run the test count if you
   use it to settle 267 + 12.

## Suggested commits

1. `history/`: move the audit, hands-on and alpha-test files (`git mv`, no edits)
2. Split handoff narrative into `history/`; add `history/README.md`
3. Add `spec/status.md`; retire `handoff.md`
4. Add the two skills
5. CLAUDE.md: docs table, the preferences-domain rule, stale lines
6. Feature specs: status blocks and stale-line fixes; plan.md; first-run brief

Then report: Step 0 findings, the section map, line counts, anything you
declined to change and why — and end with the offer to push.
