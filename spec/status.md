# ShowTools — status

**Read this first each session.** The state of play, in the present tense.
Rules are in `CLAUDE.md`, decisions in `spec/plan.md`, and what happened on
which day in `spec/history/` (never read for current rules). This file is
rewritten, not appended to: if a line has a date and a story, it belongs in
`history/`.

Repo: `~/Projects/ShowTools`, pushed to **github.com/JasonHunt3r/jhg-showtools**
(public, `main`).

## Where it stands

**Everything planned is built**, including Groups inside collections and
the range package (below). Phases 1–5, Phase 3b, Phase 4 and video
export. **319 tests** (306 core + 13 BGTools). **Library schema 13.**

| Phase | State |
|---|---|
| 1 Library + player | Built |
| 2 Composer (Edit Slides / Edit Show) | Built |
| 2a Framing, rotation, match cuts | Built, except presets (Flush), deferred |
| 2b Library manager | Built |
| 2c The lane: transitions row + images row | Built |
| 3 Music + timeline | All 7 steps built. Left: settle image stickiness |
| 3b Find Similar | Built: Delete by context, Find/Show Similar, Keep One, Keep as Group |
| Groups inside collections | Built 2026-09-24, Core through UI (`spec/plan.md`) |
| 4 Setlist export / import | Built, 4a–4d |
| E Video export | Built, E1–E5. Own spec `spec/video-export.md`. Left: a listen |
| 5 BGTools | Built, B1–B7, plus naming screens/the map view/the window opening on your screen (2026-09-25). Own spec `spec/bgtools.md`. Left: Jason's hands-on pass; the Pan and Zoom cost; telling BGTools when a library moves |

Every schema upgrade is additive and tested by opening a library of the
version before (7 rows, 8 music, 9 markers, 10 editing state, 11 rhythm
patterns, 12 their note length, 13 groups). Before an upgrade the database is copied
to `Library.sqlite.v<N>.bak`. Video export needed no schema change: a video
slide's level line is slide settings, which are JSON.

`~/Applications/ShowTools.app` is **current again, reinstalled
2026-09-25** off HEAD, so Jason can start building a show from his own
photos and music by hand (`spec/status.md`, "Also next" #2). BGTools'
desktop extension (`BGToolsControls.appex`) was killed before the swap,
on Jason's own call, rather than relaunched — it needs re-enabling by
hand before BGTools' desktop features work again.

**The real library was set aside 2026-09-24** (Jason's own call, mid this
session): `~/Pictures/ShowTools Library.noindex` is now
`~/Pictures/ShowTools Library (2026-09-24).noindex`, untouched. The next
plain launch of the real app creates a fresh, empty library at the
default path.

## What's next

**The 2026-09-24 cloud-planning work queue is done** — every item in it
(the audit batches, Groups inside collections, the range package, the
grid's keyboard, PaneKit steps 4–5, the popped-out Inspector and Timeline
panes) shipped 2026-09-24/25 and is already folded into "Where it stands"
above. Full dated story, including what each item's `swift test` run and
axtool check actually covered:
`spec/history/2026-09-25-work-queue-narrative.md`.

### The 2026-09-25 feedback worklist

Jason's own build feedback, 37 items, triaged into `spec/history/` — see
`ShowTools Feedback — Worklist for Next CC Session.md` in the repo root for
the full grouped list. **Batch 1 (PaneKit/window-layer P0s) done, except
the window-layer hierarchy write-up and pop-out audit (item 2's other
half, still open — a documentation task, not a bug):**
- **Item 9**, Settings panel off the bottom of the screen: fixed,
  scrollable and capped to the screen's visible height, checked with
  axtool (opens at 520x450).
- **Item 2**, a popped-out pane panel floating over other apps' windows:
  fixed (`.floating` is a system-wide window level, dropped to `.normal`
  while ShowTools isn't active) — build-clean, not yet seen by eye
  against a real other-app window.
- **Item 11**, BGTools' window stranded on a monitor that gets unplugged
  while already open: fixed (recenters on `didChangeScreenParameters
  Notification` if its own screen is gone) — reasoned through, untestable
  here with one monitor.
- **Item 1**, the collections column (Edit Show's list pane) growing when
  the inspector closes instead of staying put: fixed —
  `nearIsRigid` (`spec/panekit.md`, "Building a row") now also governs a
  collapse, not just a direct drag, so the freed width goes to the
  preview, matching what a drag already did. Two new `PaneControllerTests`
  pin it (each fails on the old code first). Reverses the
  "divider isolation" trade `panekit.md` documented and confirmed by hand
  on 2026-09-24 — Jason's own feedback the next day reversed it.

**Batch 2 (library/collections interactions) mostly done:**
- **Item 6**, clicking a use in Edit Show's list moved the playhead:
  fixed — a plain click now only selects; ⌥-click keeps the old jump.
  Checked with axtool: selecting a later slide leaves the preview and
  timeline at 0:00.
- **Item 3**, clicking the library pane's background switched the detail
  pane to the plain Library grid: fixed — the sidebar `List`'s selection
  binding now ignores a background click's nil write. Checked with
  axtool.
- **Item 4**, no right-click response in the main window's background:
  fixed for the Library grid's own background (Import…/New Collection…/
  Add from Library…). Checked with axtool. The sidebar's own background
  right-click wasn't separately checked — worth a look.
- **Item 5** was Jason's own mislabel, cleared up 2026-09-25: what he
  meant is item 12 (below), not a naming bug. No code change.
- **Item 15**, the Library pane's minimum width (180) read too wide:
  lowered to 140, both the split's range floor and the pane's own
  `minSize`.
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
  straight into its rename alert, skipping the right-click menu —
  `.simultaneousGesture`, not `.onTapGesture`, so the `List`'s own
  selection click still works. Checked with axtool: ⌥-click opened
  Rename Group directly.
- **Item 17** (reordering isn't implemented in collections/groups
  views) and **item 12** (groups don't create a library item) are
  **not started, on purpose.** Item 17 needs a real ordering column —
  `collection_items`/`group_items` today only order by `added_at`, so
  dragging to reorder needs a schema migration (schema 13 → 14), not
  just a UI change. Item 12 is explicitly flagged in the feedback doc's
  own Open Questions as needing a design pass before CC builds it (the
  catalog pane's own list item per group, and where group selection
  hangs off the collections list column dropdown) — Jason confirmed
  this 2026-09-25. Both are real next steps, just not one-sitting fixes.

Batch 2 is otherwise done.

**Batch 3 (frames row/transport) done, except item 19:**
- **Item 7**, the range Out marker sitting slightly left of its true
  position: fixed — `Path`'s own drawing coordinates for a `.frame()`'d
  shape aren't clipped or rescaled to that frame, so the out-marker's
  triangle (drawn pointing into negative x) bled outside its frame's
  nominal origin while the `.offset()` placement math still only cared
  about that origin — the in-marker's formula was already right, the
  out-marker's had an extra, wrong `- w`.
- **Item 8**, the frame strip's resize bar tracking the mouse at half
  speed: fixed. Root cause, found with a temporary probe logging the
  gesture's own translation: the bar sits between two views (the
  picture, the strip) whose sizes the drag itself changes, so the bar's
  own on-screen position moves mid-drag — its plain (`.local`)
  `DragGesture` was anchored to that moving frame, a feedback loop that
  measured out to almost exactly half the real drag distance at two
  different drag lengths. Anchored to the outer column instead (which
  doesn't move), matching why `StorylineView`'s own drags are already
  named coordinate spaces. Also stopped writing `frameStripHeight`
  (`@AppStorage`) on every pixel of the drag, matching PaneKit's own
  "draw live, commit on release" dividers. Checked with axtool: a 100pt
  drag now moves the bar exactly 100pt, both directions.
- **Item 18** (the frames-row position marker should be draggable with
  live scrub): **already built, no change needed.** `scrubGesture` on
  `RulerView` is a `DragGesture` computing an absolute seek from
  `location.x` on every `onChanged`, not a click-only affordance.
  Checked with axtool: dragging from 0:00 toward the 0:20 tick landed
  the playhead at 0:20.5, live.
- **Item 19** (transport pane greyed-out state) is **not started, on
  purpose** — it's literally the feedback doc's own Open Question 1
  ("what should happen when a file is dragged onto a greyed-out
  transport with no show loaded"), which the doc itself says needs a
  concrete interaction spec before CC can build it.

**Batch 4 (BGTools) partly done:**
- **Item 10**, BGTools couldn't be self-quit during the last rebuild:
  fixed in `install.sh` — it asked BGTools.app to quit only via
  `pkill` (no graceful `osascript` quit, unlike ShowTools right above
  it) and never touched `BGToolsControls.appex` at all. A Control
  Center extension runs as its own process, hosted by the system, not
  by BGTools.app — reinstalling over it while it's still running is
  exactly this symptom. Now quits BGTools.app gracefully first, and
  `pkill`s the extension by its own path too.
- **Item 21** (launch + install from a ShowTools menu, plus a setting):
  fixed — "Desktop Show…" moved out of the View menu's toolbar group
  into its own top-level "BGTools" menu; a new Settings ▸ BGTools
  toggle, "Launch BGTools when ShowTools launches," starts it silently
  (no window) at ShowTools' own launch, separate from the existing
  "Open at Login" switch (which stays in BGTools' own window, where it
  already was). Checked with axtool.
- **Item 22**, BGTools' window not staying visible across a Space
  switch: fixed — `canJoinAllSpaces`, the same treatment the Control
  Center panel already had.
- **Items 23–25 not started, on purpose:**
  - **23** (Control Center tile: two clicks instead of one, and a
    better icon) needs real hands and real Control Center registration
    to even reproduce — this environment can't drive Control Center's
    own UI, and the repo's own notes call this area cache-heavy and
    fragile (`CLAUDE.md`'s install.sh comment). The icon half also
    needs Jason's own direction on what "better" means.
  - **24** (per-screen stop) is a real feature, not a bug fix — a new
    per-monitor toggle or a "Plays Nothing" list entry, model changes
    plus a UI decision the feedback doc itself frames as "two possible
    mechanisms, pick one."
  - **25** (BGT pan & zoom, length, transition options, matching
    ShowTools' own slides) is a sizable feature port, not a fix.
  All three are real next steps, just not one-sitting fixes, same as
  items 12/17/19 above.

Batch 5 (P2 polish) not started. Five items need Jason's own decision
first (Open Questions in the feedback doc) before CC can build them.

**A preferences leak, caught and fixed mid-session:** testing item 1's
pop-out interactively wrote a scratch pop-out state into the *shared*
`com.jhg.showtools` preferences domain (`PaneKit.EditShowColumns`
changed from 141 to 140 bytes) — the exact trap `showtools-testing`
warns about. Caught by comparing against the pre-session `defaults
export` backup and restored before this note was written. Jason's real
app was running throughout and unaffected (its window never reopened
mid-session).

### Also next

1. **A listen, twice over.** (1) An exported movie against the same show
   playing: timing, crossfades, a video slide's sound against a song.
   (2) A video slide's sound in the app (V6): a clip with its middle
   dropped, a video against a song (they should just mix, no ducking),
   and whether the level glides or steps audibly — live it is set once
   per drawn frame, in an export per sample, so the export may be the
   smoother of the two.
2. **A show made from Jason's own photos and music**, imported by hand.
   This is what v1 end-to-end still needs. The demo show was seeded by a
   script, so ingest-by-drag, building a show by hand and editing it are
   untested by a person.
3. **Telling BGTools when a library moves** (B7 left it open).
4. **Expected Mac behaviour** — `spec/hig-audit.md` (audited from code
   2026-09-24; G1 fixed, unbuilt; the rest is the work queue above). Missing conventions: ⌘A, ⌘D, arrow keys
   and Quick Look in the grid; context menus on lane images, transitions
   and markers; Edit Show's commands in no menu; Edit Slides and Edit
   Show disagreeing. One real bug: **adding slides by a drop onto Edit
   Slides, a show in the Library pane or Add to Show can't be undone** (G1). Eight fix
   batches, least risky first; three decisions for Jason.

**Ken Burns → "Pan and Zoom" — done 2026-09-23** (`8db7ffc`, `a0be113`),
in the UI, the code, the slide-settings JSON keys (`panAndZoom`,
`panAndZoomSeed`) and the setlist TSV columns (`panzoom_*`). No old
spelling was kept readable. The show-level default was already `.off`;
BGTools' random-mode default was the one place still `.auto`, now `.off`
too. `~/Applications/ShowTools.app` is rebuilt and reinstalled from HEAD.
**A setlist folder or `show.json` exported before this date will lose its
Pan and Zoom setting, silently, on re-import** — confirmed by hand
against a real export. Full story: `spec/history/2026-09-23-pan-and-zoom-rename.md`.

**Pan and Zoom only zooms** (Jason, 2026-09-24): Auto is mostly a zoom,
and Custom's pan is two small frames to drag in the inspector. Wanted: a
direction, and aiming the zoom by clicking the image. In the plan, under
Later.

Parked: image stickiness, a guided first run (`spec/first-run-brief.md`),
and Flush presets from 2a.

**Next conversation: right-click menus,** area by area, with
`spec/anatomy.md` as the guide. The plan is at the end of
`spec/conventions.md`. Finish the other universals first.

## Still needs Jason's hands

- **BGTools: naming screens, the map view, the window opening on your
  screen** (built 2026-09-25, `spec/bgtools.md` items 3–5): renaming a
  monitor or a Space, the Map | List switch, and the window landing on the
  calling monitor with its Space selected — all confirmed by their actual
  effect with axtool against a scratch settings file (live updates, no
  relaunch needed; `settings.json` read back correctly), but this Mac has
  one monitor, so the parts that are *about* more than one — the map
  actually laid out to scale, the window really following the pointer
  from screen to screen, ⌥-double-click actually moving it there — are
  reasoned through from the code, not seen. Worth a particular look with
  a second monitor plugged in.
- **Edit Show's inspector popping out** (built 2026-09-25, View ▸
  "Inspector in Its Own Window," `spec/panekit.md` "The order" step 4):
  the window itself, the main window closing up, the popped-out content
  following the main window's selection, and — after a same-session fix,
  `UndoMenuState` (`spec/panekit.md`, "Pane ⇄ panel") — undo, all
  confirmed with axtool against a scratch library: `Edit ▸ Undo` reads
  the real action name and a real ⌘Z/⇧⌘Z from the popped-out window
  undoes and redoes the edit, checked against the saved show's JSON.
  Never confirmed by a real click, drag or keypress from Jason's own
  hands.
- **The timeline pane, full width under the Library pane, and popping
  out** (built 2026-09-25, `spec/panekit.md` "The order" step 5): sits
  at x=0, under the Library pane, not starting at the detail column's
  left edge; the library and detail panes grow to fill the window's full
  height when Edit Slides or the plain Library view closes it; View ▸
  "Timeline in Its Own Window" still pops it out as an ordinary window,
  now at its own full width; bare-key shortcuts (Space, J/K/L, M, I, O,
  N, arrows), Undo/Redo, and the Show/View menu's Play/Pause, Set Range,
  Zoom, Loop and Go Back/Forward items all still work from the
  popped-out window after the move; a real slide Delete shows the
  slide-removal notice and removes just that slide (not "Delete Show?" —
  a real race between two separate Delete-key handlers, found and fixed
  the same day), with ⌘Z putting it back. All confirmed with axtool
  against a scratch library. Never confirmed by a real click, drag or
  keypress from Jason's own hands.
- **The grid's keyboard** (built 2026-09-25, audit batch 7): arrow keys,
  Return-renames, and Quick Look on ⌘Y or a double-click — all confirmed
  by their actual effect with axtool (selection counts, the rename sheet,
  a screenshot of the right file in Quick Look, the panel really closing
  on a second ⌘Y even while it was the key window), never by a real
  keypress or click. Worth a particular look: whether `columnCount`'s
  worked-out math ever drifts from `.adaptive`'s own at an odd window
  width or thumbnail size (only the default 250pt tile size, at the
  window's default width, was exercised).
- **Drops onto slides and Replace Image…** (built 2026-09-24, plan.md
  "Replace a slide's image"): Replace Image… from all four menus (only
  the storyline's was actually clicked through), the storyline's drag
  Replace-or-Insert (a real internal drag confirmed both, but never
  watched by eye), and the Edit Slides list's own per-row drop (G2's
  fix) — not exercised at all, a cross-window synthetic drag wasn't
  practical to set up. Worth a particular look: whether the storyline's
  replace-zone highlight (a box around the whole slide) and the list's
  fixed 12pt insert bands feel right, and whether the pixel bands scale
  sensibly if a row's height ever changes.
- **Timeline keys** (built 2026-09-24, `spec/conventions.md` §2): arrow-key
  navigation across all four rows and Go Back/Forward — checked with
  axtool against a scratch library's saved state (times, the enabled/
  disabled menu items, `Edit ▸ Undo` staying off), never by a real
  keypress or a real look at the storyline. Worth a particular look: the
  empty-row deselect gap noted above, and whether Go Back's scroll
  restoration (the nearest slide, not the exact offset) feels right.
- **The whole range package, W6–W10** (built 2026-09-24, `spec/plan.md`
  "The range and the ruler" and "Fill the range with images"): dragging
  an end, the lock (right-click of either end, the shaded span or the
  button), I/O/⌥X still landing while locked, the range button's
  plain-click/⌥⌘-click/⇧⌥⌘-click/right-click, the shaded span's own
  right-click menu, double-clicking a song section to set the range, and
  the Fill Range with Images dialog itself — all reasoned through and
  checked with axtool against a saved show's `editor` and `slides` tables
  and screenshots, never by a real drag or a real modifier-click (axtool's
  `click` can't hold two modifiers at once, so ⌥⌘ and ⇧⌥⌘ themselves are
  unverified beyond their Show-menu equivalents). Worth a particular look:
  whether a real drag feels right — the synthetic one moved further than
  its own on-screen distance implied, which may just be a tool artifact;
  whether scrubbing still feels normal across the whole ruler now that the
  range's shaded span carries its own copy of the seek gesture alongside
  `RulerView`'s; the Fill dialog's Library tab and a Displace fill (only
  Collection and Replace were clicked through); and the one-slide-inside-
  the-range edge case in `RangeFill` (a second use of the same file for
  what continues past the range's end) — reasoned through and tested, but
  not something the plan itself spelled out, so worth Jason's own read.
- **The viewer's menus, Show in Library, and the progress line fix**
  (built 2026-09-24, `spec/conventions.md` §3, item 4): every menu opens
  with the right items and every action was confirmed by its actual
  effect with axtool (Rotation Handles and Slide Progress toggle and
  report back, Show in Library opens the panel and selects the right
  file, Hide/Show Frame Strip round-trips, the progress line fills left
  to right), but none of it has been used by a real click yet. Worth a
  particular look: the known, accepted limitation that the image vs.
  pasteboard menu goes by which image was last clicked, not by the
  right-click's own location.
- **Edit Slides', the browser's and the inspector's menus** (built
  2026-09-24, `spec/conventions.md` §3, items 3/5/6): Copy/Paste and
  Copy/Paste Settings, the quick-settings submenus, Use Defaults for All
  Slides, the browser's Select in Timeline/Play from Here/Remove from
  Show, and both inspector section menus — all confirmed by their actual
  effect with axtool (slide counts and settings genuinely changed, not
  just the menu opening), never by a real click. Worth a particular
  look: Copy/Paste Settings are meant to swap in over Copy/Paste only
  while ⌥ is held, but are built as four always-visible items instead
  (SwiftUI's `.contextMenu` can't declare AppKit's alternate items) — if
  that reads as clutter in practice, the ⌥-swap is its own follow-up.
- **The library panel** (built 2026-09-24, `spec/panekit.md`, "Step 4,
  second piece"): opens and shows the whole library correctly, checked
  with axtool against a scratch library, but a real drag from it (its own
  reason for existing — filling a new collection with the panel floating
  over it) hasn't been tried by hand.
- **The grid's list view at the size slider's minimum, and the panel's
  slider now independent of the main window's** (Jason, 2026-09-24,
  `spec/windows.md` answer 6): checked with axtool — dragging the slider
  to its floor and back switches cleanly between a single-column list
  (small icon, filename, full-width selection highlight) and the tile
  grid, selection carries across the switch; the library panel's slider
  and the main window's grid now keep their own sizes (`gridTileSize` vs
  `gridTileSize.panel`), checked with both windows open at once, one in
  list view and the other mid-size — but never watched by a real drag of
  the actual slider control.
- **Audit G1 and the audio-naming pass** (`7c1613a`, `dcf47c2`): both
  build and the app launches, but the hands-on checks weren't done this
  session — see the work queue above.
- **Context menus C1–C3** (Remove Image/Transition/Marker): build and
  test clean, but not confirmed by a real click — the storyline canvas
  resisted synthetic clicking this session.
- **Groups in the Library pane** (built 2026-09-24): drag-to-add from the
  grid and from Finder, nested folding, New Group naming, the delete
  notice's wording, the browser's group filter, and Keep as Group. Also
  new: **dragging a group onto another to nest it, onto its own
  collection to un-nest it, and onto a different collection**, with the
  "images will be added" notice and its suppression checkbox. All of it
  only smoke-tested (launch, no crash), not clicked by a person.
- **⇧-click in the Library grid and the storyline** (batch 4, built
  2026-09-24): `GridSelection`'s logic is unit-tested against the audit's
  own worked examples, but a real ⇧-click, ⇧-click, ⇧-click hasn't been
  tried by hand in either place.
- **The menus batch 5 built 2026-09-24**: the Show and View menu items,
  Get Info from a slide selection, Show ▸ Play starting at the
  selection, and Help ▸ Keyboard Shortcuts — all reasoned through and
  compiled clean, but a menu can only really be checked by opening it.
  Worth a particular look: the toolbar's Inspector button and ⌘1/⌘2 lost
  or gained their shortcuts moving to the View menu, so it's worth
  confirming nothing doubled up or went silent.
- **The Rhythm tool** (step 7): the panel's look (the space around the
  form, the notation's size: a staff space is 5.5 pt), Listen by ear on
  real music, Space stopping Listen, and whether 145 BPM is right for
  Fly Me to the Moon (or double).
- **Listening:** music sync, fades, crossfades; Bluetooth headphones'
  delay (the output latency is subtracted, but it's untested).
- **Inspector sliders' live preview** — built (`b66b4af`) but never
  watched by eye; the commit says so.
- **Dragging a song in from Finder or Music.**
- **Look and feel:** the row handles (10 pt wide), the drawers, the level
  line's handles, whether a line on every clip is too busy in the thin
  images row, and the transport's new toggles.
- **BGTools:** unlocking a private library with Touch ID, the panel
  closing on a click elsewhere, Space-switch pausing — not yet re-done
  against the nested BGTools.
- **From before Phase 3:** cross-app drags from Finder and Photos, Touch
  ID and the Mac's password, pinch, a second screen, cursors, and one
  real ⌘Z with the Info panel focused.

## Open questions

- **Image stickiness (2c)**, at the end of Phase 3: should a lane image
  stay at its time on the clock, or move with the slide it starts over
  when slides are trimmed or reordered? For now it stays on the clock.
- **Windows of their own** (`spec/windows.md`): which areas detach, the
  Slide Editor, the library panel and Show in Library. Jason answered six
  of seven questions 2026-09-24; what comes first is still open. Its prerequisite is moving a show's
  editing state out of the views, which the audit's menu work wants too.
- **Simple things fast** (`spec/simple-things-fast.md`; was "a simple
  way in"). The editor does a lot, but simple things aren't fast. There
  are three answers: the guided first run, playing a library or
  collection without building a show, and three levels (Basic, Advanced,
  "Bring it on!"). Four questions for Jason.

## Known issues

- **A caught, non-fatal exception on the Library sidebar's right-click**
  (`~/Library/Logs/ShowTools-exception.log`, 2026-09-25 08:42:35 and
  08:42:36 UTC): `NSTableViewException`, "Row index -1 out of row range,"
  from `-[NSTableView menuForEvent:]` on `SwiftUIOutlineListView` — a
  stale/negative row index when a context menu is asked for. Logged
  twice, a second apart, with no crash dialog and not witnessed by
  Jason — `ExceptionProbe` catches exceptions AppKit's own event loop may
  already be recovering from, so a log entry isn't proof of a visible
  crash. Not investigated: found while looking at the log for an
  unrelated reason, no repro yet, no PaneKit/pop-out frames in the stack
  so unrelated to that work.
- **The layout-loop crash — fixed 2026-09-23, and its 2026-09-24
  recurrence also fixed.** `NSGenericException` from AppKit's layout-loop
  guard; root cause was SwiftUI's `.inspector()` modifier, fixed by
  porting Edit Slides' inspector onto `ColumnsSplitView`
  (`spec/edit-slides-inspector-port.md`). Recurred once more from a
  `SingleKeys` monitor on the sidebar `List`, fixed by moving it to the
  `NavigationSplitView`. **Lesson kept live:** `.background(SingleKeys)`
  is safe on a plain SwiftUI container, not on a `List` or anything else
  AppKit backs with its own constraint-based layout — check before adding
  one to Edit Slides' or the storyline's own Lists. Full story:
  `spec/history/2026-09-23-crash-hunt.md`,
  `spec/history/2026-09-23-crash-hunt-session2.md`,
  `spec/history/2026-09-23-crash-hunt-session3.md`.
- **Pulling the inspector's divider far to the left breaks the layout**
  ("smashes both sides out off the screen"). Seen once in a test copy
  dragging from the right edge to x=300. `revealByDragging` is the obvious
  suspect — it clamps the width it sets, but nothing re-checks the columns
  as a whole. Needs reproducing before anything is changed.
- **⌥⌘0 (Restore Default Layout) raised the layout-loop exception once**,
  and killed the app, on 2026-09-23: *before* the cause was confirmed as
  SwiftUI's `.inspector()` and fixed. Not seen since the fix; probably that
  same crash. The Library pane was a suspect only by coincidence (Jason). Its
  known bugs are display bugs. `DefaultLayout` still skips the Library pane on
  that stale reasoning, which is worth retrying.
- **A song lying wholly inside another** plays over it without crossfading
  (only a partial overlap crossfades). Level tops out at 100%.
- **The last slide cuts to the background** when something runs past the
  slides; a fade could come later.
- **The row drawers hold no controls yet.** Scrub audio isn't built;
  scrubbing is silent.
- **CPU** is about 33–37% while the editor plays; memory about 430 MB.
  BGTools' desktop mode is ~2% since B6, except while Pan and Zoom moves,
  which costs about 40% of a core because it really does redraw every
  frame — worth a look. It's why BGTools' random-mode default was flipped
  to `.off` 2026-09-23 (it's opt-in now, not a cost every random desktop
  show pays).
- **Video:** it can't go in the lane yet. The frame strip shows a video's
  first frame, the onion skin skips video slides, and `stcli render` draws
  a video slide as the background colour — only `stcli movie` and the app
  go through `MovieMedia`. A video slide's sound is decoded whole into
  memory when exporting; fine for slides, worth revisiting if whole films
  ever become slides.
- The zoomed-out work area doesn't draw a lane image's overhang past the
  frame.
- Accordion was dropped, and Page Curl is offered as "Page Turn".

## Test things installed on Jason's Mac

`ShowTools.app` in `~/Applications` (the real one, with BGTools and the
tiles inside), `build/DesktopProbe.app` (not running), and XcodeGen
(`brew install xcodegen`, now required to build the app at all). Stale
Background Task Management entries for `com.jhg.bgtools` and two
`com.jhg.nestprobe` ids remain — `sfltool resetbtm` would clear them but
resets every app's login items, so they are left alone.

## Quick start

```sh
swift test                                  # 306 core + 13 BGTools tests
./make-app.sh                               # → build/ShowTools.app
tools/make-test-library.sh <scratch>/STTest # scratch library + generated media
open -n --env SHOWTOOLS_LIBRARY=<scratch>/STTest/TestLib.noindex build/ShowTools.app
```

Before launching any test copy, read the `showtools-testing` skill: a test
copy shares Jason's preferences domain, and a crashed one shuts his real
app out.
