# 2026-09-25 — the feedback worklist, batches 1–5

Jason's own build feedback, `ShowTools Feedback — Worklist for Next CC
Session.md` (repo root), 37 items. Worked through in five batches, grouped
by shared code rather than the doc's own flat priority order. This is the
dated story — what was fixed, how, and what each fix was checked against.
Current state (what's done, what's left) lives in `spec/status.md`.

## Batch 1 — PaneKit / window-layer P0s

- **Item 9**, Settings panel off the bottom of the screen: the `Form` used
  `.fixedSize(vertical: true)` with no cap. Wrapped in a `ScrollView`,
  capped to the screen's visible height minus a margin. Checked with
  axtool: opens at 520x450, inside the visible frame.
- **Item 2**, a popped-out pane panel floating over other apps' windows:
  `isFloatingPanel` sets `.floating`, a *system-wide* window level, not an
  app-local one. Now drops to `.normal` whenever ShowTools isn't the
  active app, back to `.floating` when it is. Build-clean; not seen by eye
  against a real other-app window.
- **Item 11**, BGTools' window stranded on a monitor that gets unplugged
  while already open: `showWindow()` only recentered on the calling
  monitor when the window was (re)opened, not while already visible. Now
  listens for `NSApplication.didChangeScreenParametersNotification` and
  recenters onto the main screen if its own screen is gone. Reasoned
  through; untestable here with one monitor.
- **Item 1**, the collections column (Edit Show's list pane) growing when
  the inspector closes: `nearIsRigid` (`spec/panekit.md`, "Building a
  row") kept `near` fixed-width on a direct near|far *drag*, but a
  *collapse* skipped the link on purpose — closing the inspector still
  grew the list column. `PaneController.setOpen` now applies the same
  `linkedAncestor` delta a drag would, and `.row`'s comboRange floor
  drops to `near.minSize + handleThickness` under `nearIsRigid` so the
  stored value doesn't get clamped back up before it takes effect. Two
  new `PaneControllerTests` (in `PaneKit/Tests/`, run via `cd PaneKit &&
  swift test` — not part of the root `swift test`'s 306) pin it; both
  fail on the old code first. **Reverses the "divider isolation" trade
  `panekit.md` documented and confirmed by hand on 2026-09-24** — Jason's
  own feedback the next day called it wrong.
- Item 2's other half — a documented window-layer hierarchy and an audit
  of the other pop-outs — was left open; it's a writing task, not a bug.

**A preferences leak, caught and fixed mid-session:** testing item 1's
pop-out interactively wrote a scratch pop-out state into the *shared*
`com.jhg.showtools` preferences domain (`PaneKit.EditShowColumns` changed
from 141 to 140 bytes) — the exact trap `showtools-testing` warns about.
Caught by comparing against the pre-session `defaults export` backup and
restored immediately. Jason's real app was running throughout and
unaffected (its window never reopened mid-session).

## Batch 2 — library/collections interactions

- **Item 6**, clicking a use in Edit Show's list moved the playhead:
  `engine.showSlide(id:)` ran on every plain click. Now only on
  ⌥-click, reading `NSEvent.modifierFlags` live (the same trick
  `StorylineView`/`EditShowView` already use). Checked with axtool:
  selecting a later slide leaves the preview and timeline at 0:00; only
  the list selection changes.
- **Item 3**, clicking the library pane's background switched the detail
  pane to the plain Library grid: a plain `List(selection:)` clears its
  selection to `nil` on a background click, and `detailView`'s `default`
  case for a `nil` sidebar is the plain grid. The selection binding now
  ignores a `nil` write — there's always something selectable (the
  Library row itself). Checked with axtool.
- **Item 4**, no right-click response in the main window's background:
  the Library grid's near-invisible background layer (used for
  tap-to-deselect) had no `.contextMenu`. Added one: Import…/New
  Collection…/Add from Library…. Checked with axtool. The sidebar's own
  background right-click wasn't separately checked.
- **Item 5** turned out to be Jason's own mislabel, cleared up
  2026-09-25 in conversation: what he meant is item 12, not a naming
  bug. Verified anyway before that came up — drove the real menu path
  (right-click ▸ Add to Group ▸ New Group…) with axtool end to end,
  typed a name, confirmed the library's `groups` table held exactly
  that name. No code change.
- **Item 15**, the Library pane's minimum width (180) too wide: lowered
  to 140, both the split's range floor and the pane's own `minSize`.
- **Item 16**, deleting a collection or group always left the files
  behind: both now offer a real "Also delete the files/images from the
  library" checkbox. The collection-delete flow moved off SwiftUI's
  `.confirmationDialog` (can't carry a checkbox) onto an `NSAlert`, the
  same synchronous shape `GroupDeleteNotice` already used for groups —
  new `CollectionDeleteNotice` in `SlideInspector.swift`. Checked with
  axtool: the alert shows the checkbox with its own label, not the
  suppression button's default text.
- **Item 28**, "Change Library…" added to the library header's
  right-click menu (same action as File ▸ Open Library…).
- **Item 32**, ⌥-click a sidebar name (collection/group/show) jumps
  straight into its rename alert: `.simultaneousGesture`, not
  `.onTapGesture` (the latter would steal the List's own selection
  click). Checked with axtool: ⌥-click opened Rename Group directly.
- **Items 17 and 12 not started, on purpose.** Item 17 (reordering)
  needs a real ordering column — `collection_items`/`group_items` today
  only order by `added_at`, so dragging to reorder needs a schema
  migration (13 → 14), not just a UI change. Item 12 (groups don't
  create a library item) is explicitly flagged in the feedback doc's own
  Open Questions as needing a design pass first (the catalog pane's own
  list item per group, and where group selection hangs off the
  collections list column dropdown) — Jason confirmed this reading
  2026-09-25.

## Batch 3 — frames row / transport

- **Item 7**, the range Out marker sitting slightly left of its true
  position: `Path`'s own drawing coordinates for a `.frame()`'d shape
  aren't clipped or rescaled to that frame, so the out-marker's triangle
  (drawn pointing into negative x) bled outside its frame's nominal
  origin while the `.offset()` placement math still only cared about
  that origin. The in-marker's formula was already right; the
  out-marker's had an extra, wrong `- w` (7pt).
- **Item 8**, the frame strip's resize bar tracking the mouse at half
  speed: found with a temporary probe (logged to a file, removed after)
  that the gesture's own final `translation` topped out at half the real
  drag distance, at two different drag lengths (100pt → -50.0, 30pt →
  -15.0). Ruled out the synthetic-drag tool itself first — a control
  drag on a known-good PaneKit divider tracked a 40pt drag perfectly.
  Root cause: the bar sits between two views (the picture, the strip)
  whose sizes the drag itself changes, so the bar's own on-screen
  position moves mid-drag; its plain (`.local`) `DragGesture` was
  anchored to that moving frame — a feedback loop. Anchored to the outer
  column instead (`.coordinateSpace(name: "previewColumn")`), matching
  why `StorylineView`'s own drags are already named coordinate spaces.
  Also stopped writing `frameStripHeight` (`@AppStorage`) on every pixel
  of the drag, matching PaneKit's own "draw live, commit on release"
  dividers (not the root cause, but the same discipline). Checked with
  axtool: a 100pt drag now moves the bar exactly 100pt, both directions.
- **Item 18** (frames-row position marker draggable with live scrub):
  already built — `scrubGesture` on `RulerView` computes an absolute
  seek from `location.x` on every `onChanged`, not a click-only
  affordance. Checked with axtool: dragging from 0:00 toward the 0:20
  tick landed the playhead at 0:20.5, live. No change needed.
- **Item 19** (transport pane greyed-out state) not started, on purpose
  — it's the feedback doc's own Open Question 1, which the doc itself
  says needs a concrete interaction spec before CC can build it.

## Batch 4 — BGTools

- **Item 10**, BGTools couldn't be self-quit during the last rebuild:
  `install.sh` asked BGTools.app to quit only via `pkill` (no graceful
  `osascript` quit, unlike ShowTools right above it) and never touched
  `BGToolsControls.appex` at all — a Control Center extension runs as
  its own process, hosted by the system, not by BGTools.app, so
  reinstalling over it while it's still running is exactly this
  symptom. Now quits BGTools.app gracefully first, and `pkill`s the
  extension by its own path too.
- **Item 21** (launch + install from a ShowTools menu, plus a setting):
  "Desktop Show…" moved out of the View menu's toolbar group into its
  own top-level "BGTools" menu; a new Settings ▸ BGTools toggle,
  "Launch BGTools when ShowTools launches," starts it silently (no
  window) at ShowTools' own launch — separate from the existing "Open
  at Login" switch, which stays in BGTools' own window where it already
  was. Checked with axtool.
- **Item 22**, BGTools' window not staying visible across a Space
  switch: `canJoinAllSpaces`, the same treatment the Control Center
  panel already had.
- **Items 23–25 not started, on purpose.** 23 (Control Center tile
  needing two clicks, and a better icon) needs real hands and real
  Control Center registration to even reproduce — this environment
  can't drive Control Center's own UI, and the repo's own notes call
  that area cache-heavy and fragile; the icon half also needs Jason's
  own direction on what "better" means. 24 (per-screen stop) is a real
  feature — a new per-monitor toggle or a "Plays Nothing" list entry,
  model changes plus a UI decision the feedback doc itself frames as
  "two possible mechanisms, pick one." 25 (BGT pan & zoom, length,
  transition options matching ShowTools' own slides) is a sizable
  feature port, not a fix.

## Batch 5 — P2 polish

Jason chose this scope 2026-09-25 (asked directly): build the two real
code items, leave the rest for design direction.

- **Item 30** (frames row collapses to a stacked handle): the "collapse"
  half was already built — every PaneKit split collapses to its own
  edge handle by default — just not discoverable. Added View ▸ "Show
  Timeline" (⌘⌥T), matching Show Library/Frame Strip/Inspector's own
  toggles right above it. The "stacked" half depends on item 13
  (Collections' own closed-drawer state stacking against the closed
  inspector), which was never built either — a real, open-ended pattern
  to design, not touched here. Checked with axtool: toggling it
  collapses the pane (library/detail grow to fill the full height) and
  restores it correctly.
- **Item 31** (scale-to-fill, as a ShowTools effect and a BGT setting):
  already fully built, both halves, no change needed. `Fit.fill` has
  existed in the core model all along; ShowTools' own `SlideInspector`'s
  Fit picker already iterates every `Fit` case, and BGTools' Random
  Pictures settings (`MainWindow.swift`, `RandomPicturesDetail`) already
  has the identical picker. Same pattern as item 18 — feedback
  describing something the codebase had already caught up to.
- **Items 26, 27, 29 not started, on purpose.** 26 (kill the rounded
  header-bar controls for a tighter "Pro" look) and 27 (app-wide
  corner-radius override) are visual redesigns with no existing token to
  hang off, not fixes — guessing risks producing something that just
  looks wrong. 29 (an icon for each app) needs actual icon artwork, not
  code. All three need Jason's own direction first.

## What's left, going into the next discussion

- **Item 12** and **item 17** (batch 2) — need a design pass and a
  schema migration respectively.
- **Items 23, 24, 25** (batch 4) — need real hands, a mechanism choice,
  and a feature port respectively.
- **Items 26, 27, 29** (batch 5) — need Jason's own design/artwork
  direction.
- **Five Open Questions** from the feedback doc itself (greyed-transport
  drag target, glass/vibrancy in light mode, Show Similar's engine,
  large-library DB/indexing, the collections list column dropdown) —
  none buildable without Jason's call first.
- Item 2's window-layer hierarchy write-up and pop-out audit (batch 1).

Every fix above shipped as its own commit on `main`, pushed after each
batch; `swift test` (306 core + 13 BGTools, plus 23 in `PaneKit/` on its
own) and `./make-app.sh` stayed clean throughout.
