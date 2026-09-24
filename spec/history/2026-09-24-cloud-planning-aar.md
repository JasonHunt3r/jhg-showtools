# After-action review: the cloud planning session (2026-09-24)

A long evening's session with Claude Code in the cloud: a Linux container
holding a copy of the repo, with no Mac and no Swift toolchain. Nothing
could be built or run, so the session did what doesn't need a Mac:
auditing, naming, planning, and design. 35 commits, from `0250aee` to
`5d72224`, on branch `claude/cloud-clauding-4lij0h`, then merged into
`main` (a fast-forward).

## What we set out to do

Start from the question "what in the plan could be cooked without a
Mac?" Jason's answer: the expected Mac behaviours that were never built
(the Edit menu, right-click, arrow keys and ⇧ selection). Measure the
app against Apple's guidelines and Mac habits.

## What happened

It grew, one idea leading to the next:

1. **The audit** (`spec/hig-audit.md`): what's missing, with file and
   line. Sections: A the Edit menu, B the grid, C context menus, D the
   Library pane, E the timeline, F the menu bar, G Edit Slides vs Edit
   Show, H making new things, I panes lost past the edge. Eight fix
   batches, least risky first.
2. **The anatomy** (`spec/anatomy.md`): one name for every area, how they
   nest, the picture's layers, what affects what.
3. **Renames:** the edit zone became the **timeline pane**; songs became
   **audio clips** in the **audio row**; the sidebar became the **Library
   pane**; "a simple way in" became **simple things fast**.
4. **Windows of their own** (`spec/windows.md`): panes that pop out as
   panels or windows, the Slide Editor, the swipe-behind idea, panes
   closing to an edge with visible handles.
5. **Simple things fast** (`spec/simple-things-fast.md`): the first run,
   Quick Show, the New Show panel, levels (Basic, Advanced, "Bring it
   on!").
6. **Conventions** (`spec/conventions.md`): what each gesture, key,
   drop and Edit-menu item means everywhere, marked Built, Settled,
   Proposed or Open, plus a log of conventions found by use.
7. **The design manual's kernel** (`spec/how-we-design.md`): the six
   pillars of a slideshow (pictures, order, length, transition,
   movement, audio), perceptual efficiency, and each principle with its
   story.
8. **The crash hunt, debriefed** (`2026-09-24-crash-hunt-debrief.md`),
   in Jason's words.
9. **PaneKit** (`spec/panekit.md`): our own reusable pane library, in
   Finder's shape (two panes and one divider, nested), with edge handles,
   pop-out and layout transactions. It replaces the built-in split views,
   and is meant for every Mac app Jason makes.

**Code changed** (not built, since the container can't; to be checked on
the Mac):
- `7c1613a`: adding slides by a drop onto Edit Slides, onto a show in the
  Library pane, or by Add to Show is now undoable (audit G1). `append`'s
  undo parameter no longer defaults to nil.
- `dcf47c2`: user-facing "song" and "music" became "audio" (row title
  and icon, grid filter and badge, menu and undo names, help text).
  `TimelineRow.Kind.music` keeps its saved raw value.
- `DefaultLayout.swift`: two comments marked stale or unproven (the
  sidebar claim, the one-change-per-turn staging). Behaviour unchanged.

## What went well

- **Planning where it's cheap.** No Mac was needed for any of this, and
  every decision is now written down before code is spent on it.
- **Jason's answers settled things fast.** Short answers to specific
  questions, recorded as they came, closed dozens of open items.
- **Checking the code before claiming.** Several ideas turned out to
  exist already, partly: `DefaultLayout` already captures a layout by
  hand; BGTools already has the six pillars; the app isn't sandboxed, so
  Photos needs no paid membership.
- **Names first.** The anatomy guide made every later conversation
  clearer, and the renames removed real ambiguity.

## What didn't

- **Stale knowledge was repeated as fact.** A code comment said setting
  the sidebar caused the layout-loop crash; it was written before the
  real cause (`.inspector()`) was found. Claude repeated it until Jason
  caught it. Now in `spec/how-we-design.md`: *stale knowledge is a guess
  too.*
- **Rules stated too strongly.** "The same action gives the same result
  everywhere" and "every empty place gets a button" were too heavy-handed.
  Jason reworded both: strive for one language and depart knowingly;
  a container you're meant to fill gets a button. Claude's part is to
  point out where a choice departs from the HIG or tradition; Jason
  decides.
- **Wording that read as the opposite.** "That's paradoxical": Claude's
  reply about the cost of leaving the built-ins read as disagreement when
  it was agreement.
- **Left and right, and which pane is which.** A small mix-up about the
  vanished pane took two turns to settle. The anatomy's names are there
  to prevent exactly that.

## What's next

`spec/status.md`, "Work queue for the Mac", in order. In short: build
and check the two code changes; ⌘A in the grid (top priority); the rest
of audit batches 1 and 2; the selection logic with tests; the PaneKit
harness. Then the right-click conversation, area by area.

## Lessons for the ops manual

- A cloud session is for work that doesn't need the Mac: audits, specs,
  names, decisions, and small code changes clearly marked unbuilt.
- Record decisions the moment they're made, in the spec they belong to,
  with the date and who made them.
- Date every belief, and check it against what's been learned since
  before building on it.
- While a Mac session works on the same branch, the cloud session keeps
  to docs, both sessions pull before starting, and each pushes before
  the other needs its work.

---

# Part two: after the first merge (later the same night)

About 50 more commits, from `ad1c70a` to `9fade89`. Jason reset his
tokens, so the Mac session worked through the queue at the same time;
the cloud session kept to docs, except PaneKit, and merged its work into
`main` at each natural break.

## What happened

1. **The right-click conversation, all eight stops**
   (`spec/conventions.md` §3, "Progress"): the Library pane, the Library
   grid, Edit Slides, the viewer, the browser, the inspector, the
   timeline pane (in two halves), and the windows around the main one.
   Rules that came out of it:
   - **Show in Finder is for a library's location only**; files get Show
     in Library.
   - **Quick settings as submenus** (Length ▸, Transition ▸, Pan and
     Zoom ▸).
   - **Copy Settings and Paste Settings as ⌥ alternates.**
   - **Select ▸** for what's under the pointer, keeping ⌥-click free.
   - **Export ▸** as one submenu wherever export appears.
   - **The player has no Close**: it's the star of the show.
2. **New decisions along the way:**
   - **Groups inside collections** ("a book cart"), decided in full and
     then built by the Mac the same night (`spec/plan.md`);
   - **Group Similar → Find Similar Images**, with Keep as Group;
   - **Replace Image…**, on right-click and by dropping onto a slide;
   - **audio rows stack**, for crossfading music and sound over it. The
     mix already sums, live and in export;
   - **a show from one picture**, which the model already allows.
3. **The Library pane** (the sidebar renamed: "sidebar" named a position,
   not a thing).
4. **Leaving the built-in split views** for our own: first as a leaning,
   then as **PaneKit** (`spec/panekit.md`). Its form grew out of Jason's
   points in turn:
   - Finder's shape, two panes and one divider, nested;
   - reusable in any Mac app;
   - pop-out built in;
   - layout transactions instead of staging.
5. **Jason's first-test work order** (`2026-09-24-work-order.md`, written
   with App Claude): folded into the plan, `spec/bgtools.md` and the
   queue. Its nine proposals were settled one by one. Two outcomes worth
   remembering:
   - the playhead stays **out of ⌘Z**, with its own Go Back (⌘[), so
     A/B-ing isn't a fight with undo;
   - Fill Range **always fits exactly**, and shows feedback instead of
     greying choices out.
6. **The queue reordered** (`spec/status.md`, "The order from here"):
   PaneKit first, then things that share code, grouped so each area is
   opened once.
7. **PaneKit's first cut, written overnight, uncompiled.** It's a library,
   14 layout tests and a test app with three shapes (Finder, Mail,
   ShowTools). It moved into **its own package**, `PaneKit/`, so code
   that had never compiled couldn't break ShowTools' build.

## What went well

- **The anatomy made the right-click conversation fast.** Eight stops,
  mostly one-word answers, because every area had a name to ask about.
- **Checking the code before claiming kept paying.** An audio clip has no
  row, so stacking is a new field. The mix already sums. The app isn't
  sandboxed, so Photos needs no paid account. `DefaultLayout` had already
  captured a layout by hand. BGTools already had the six pillars.
- **Two sessions on one repo worked:** a clean merge each time but one,
  and that conflict (both editing the queue) kept both sides.
- **Isolating uncompiled code** in its own package.

## What didn't

- **Context was lost twice**, and the cause was outside the session: a
  brief power outage at Jason's house reset his routers and dropped the
  connection (Jason: "it wasn't your failing"). What was lost was the
  conversation in between: a commit drawing the maps, made against
  Jason's "hold off", appeared with no memory of it, and later five
  answers arrived for questions no longer in view. Both were handled by
  saying so and asking, rather than guessing. The maps were kept once
  Jason saw them. The work itself survived, because every step had been
  committed and pushed as it was done.
- **The work order's claim that the viewer and ruler menus weren't
  settled** was out of date by the time it arrived. Every pointer was
  checked against `main` before use, as it asked.
- **A question that wasn't one:** asking whether the library panel and the
  Slide Editor should "inherit" menus read as a test. It was a poor
  question.
- **The Mac session left the timeline's arrow keys unwired "waiting on a
  decision"** that had already been made. Decisions need to be where
  the builder looks: the conventions *and* the queue.

## Lessons for the ops manual (added)

- **Say when context is missing.** Answer from what's on disk and in git,
  and ask for what isn't. Never map answers onto guessed questions.
- **Commit and push at each step** (CLAUDE.md's rule) is also the
  insurance against a dropped connection: when the conversation went,
  the work didn't.
- **A decision the builder can't find isn't made.** Put it in the spec,
  and in the queue item that uses it.
- **Keep untested code where it can't break tested code:** its own
  package, or at least its own target, until it compiles.
- **Merge often** when two sessions share a repo, and read the other
  session's changes before merging.
