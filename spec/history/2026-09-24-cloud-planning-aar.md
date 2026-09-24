# After-action review: the cloud planning session (2026-09-24)

A long evening's session with Claude Code in the cloud: a Linux container
holding a copy of the repo, with no Mac and no Swift toolchain. Nothing
could be built or run, so the session did what doesn't need a Mac:
auditing, naming, planning, and design. 35 commits, from `0250aee` to
`5d72224`, on branch `claude/cloud-clauding-4lij0h`.

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
