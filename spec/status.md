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
export. **330 tests** (317 core + 13 BGTools). **Library schema 14.**

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
| 5 BGTools | Built, B1–B7, plus naming screens/the map view/the window opening on your screen (2026-09-25). Own spec `spec/bgtools.md`. Left: its own "Next up" list (items 23–25, after the ShowTools fixes), Jason's hands-on pass, the Pan and Zoom cost, telling BGTools when a library moves |

Every schema upgrade is additive and tested by opening a library of the
version before (7 rows, 8 music, 9 markers, 10 editing state, 11 rhythm
patterns, 12 their note length, 13 groups, 14 a drag order for a
collection's/group's files). Before an upgrade the database is copied
to `Library.sqlite.v<N>.bak`. Video export needed no schema change: a video
slide's level line is slide settings, which are JSON.

`~/Applications/ShowTools.app` was last reinstalled 2026-09-25 17:30,
at `9bccebe` (Item 17's first attempt, the one that didn't work by hand).
It doesn't have the rebuilt drag-to-reorder, the pile or the Undo fix
from the evening (`d3b25a2` onwards) — reinstall with `install.sh` to
get them. Reinstalling stops the real BGTools instance
(`install.sh`'s own quit sequence). BGTools'
desktop extension (`BGToolsControls.appex`) was also killed before that
morning's swap, on Jason's own call, rather than relaunched — it still
needs re-enabling by hand before BGTools' desktop features work again.

**The real library was set aside 2026-09-24** (Jason's own call, mid this
session): `~/Pictures/ShowTools Library.noindex` is now
`~/Pictures/ShowTools Library (2026-09-24).noindex`, untouched. The next
plain launch of the real app creates a fresh, empty library at the
default path.

## What's next

**NEXT TASK: lift drag-to-reorder into its own package** (ReorderKit,
like PaneKit: a local package in the repo, its own tests and harness), so
other apps can use it — agreed with Jason 2026-09-25, once the behaviour
was settled. What moves: `ShowToolsCore/Reorder.swift` (and
`ReorderTests`) and `ShowToolsApp/ReorderDrag.swift`; the grid's wiring in
`LibraryGridView` (`startDrag`, `commitReorder`, `slot(at:)`, the fly-in and
landing) is the part to turn into the package's API. The design, its
terms and every dial: `spec/plan.md`, "Reordering".

**The 2026-09-24 cloud-planning work queue is done** — every item in it
(the audit batches, Groups inside collections, the range package, the
grid's keyboard, PaneKit steps 4–5, the popped-out Inspector and Timeline
panes) shipped 2026-09-24/25 and is already folded into "Where it stands"
above. Full dated story, including what each item's `swift test` run and
axtool check actually covered:
`spec/history/2026-09-25-work-queue-narrative.md`.

### The 2026-09-25 feedback worklist

Jason's own build feedback, `ShowTools Feedback — Worklist for Next CC
Session.md` (repo root), 37 items, worked through in batches grouped
by shared code. **27 of 37 done** (batches 1–6 below); each fix checked
with axtool against a scratch library, not just compiled. Full dated
story — root causes, what each check actually covered, the commit for
each: `spec/history/2026-09-25-feedback-worklist-batches.md`.

| Batch | Done |
|---|---|
| 1 — PaneKit/window-layer | Items 1, 2, 9, 11 |
| 2 — library/collections | Items 3, 4, 6, 15, 16, 28, 32 (item 5 was a mislabel, no code needed) |
| 3 — frames row/transport | Items 7, 8, 18 (18 was already built) |
| 4 — BGTools | Items 10, 21, 22 |
| 5 — P2 polish | Items 30, 31 (31 was already built) |
| 6 — transport/icon, discussed 2026-09-25 | Item 19; item 12's icon half (its promotion idea is still open, above) |

**Batch 6 — decided/built 2026-09-25** (this discussion):
- **Item 19** (transport greyed-out state) — **built**: the timeline
  pane's split now stays open in both edit modes (`MainView.isShowOpen`,
  was `isEditingShow`, gated on `mode == .show` too); Edit Slides shows
  `TimelinePanePlaceholder` (`EditShowTimelinePane.swift`), the same
  chrome dimmed and inert, instead of the pane closing and the window
  reflowing. Checked with axtool against the scratch library: the
  placeholder's "Switch to Edit Show to use the timeline" reads correctly
  in Edit Slides, and clicking back to Edit Show restores the real,
  interactive transport and storyline, screenshotted both ways. **Left,
  on purpose:** what a drop onto the greyed bar should do (item 33) — an
  Open Question Jason wants to answer once he has a working copy to play
  with, not before.
- **Item 12** (groups → a library item / catalog folder) — Jason's actual
  intent was already built 2026-09-24 (the Library pane's collapsible
  groups-and-shows list); the only missing piece, the icon convention
  (solid folder for a collection, outline for a group), is **built**
  (`collectionRow` now uses `folder.fill`, confirmed by screenshot). The
  bigger idea Jason raised alongside it — **promoting a group to its own
  collection** — is still a design question (`spec/plan.md`, "Groups
  inside collections," "Promotion"): what happens to the original group,
  and whether nested sub-groups come along.
- **Item 17 / 38** (drag-to-reorder) — **built and tried by Jason's
  hand, 2026-09-25**: an empty gap follows the pointer, one drop handler
  for the whole grid, a drop saves what's on screen, Undo Reorder works;
  several files drag as a tidy pile with a count badge, fly in on pickup
  and spring into place on drop; the grid scrolls near its edges, faster
  and with the pile shrinking as it nears them. Design, terms and dials:
  `spec/plan.md`, "Reordering". Story: `spec/history/2026-09-25-drag-reorder-rebuild.md`.
  Left: the plain Library's sort strip (Known issues).
- **Items 23–25** — queued as their own BGTools work list, to pick up
  once the ShowTools fixes above are done: `spec/bgtools.md`, "Next up —
  queued 2026-09-25, after the ShowTools fixes."
- **Items 26, 27, 29** (header-bar restyling, corner-radius override, app
  icons) — Jason's counter-proposal: a small **live value-changer
  panel** (corner radius, text size, control size, container-border
  visibility, …) as a reusable dev tool for tuning any app's look by
  trial and error, rather than one-off asks each needing a build. Not
  scoped yet: still needs a design pass (where its values live —
  UserDefaults keys the views already read, most likely — and which knobs
  it exposes first).
- Item 2's other half (a written window-layer hierarchy, and an audit of
  the built pop-outs against it) — still open, not started.
- **Simple things fast** — Jason confirmed 2026-09-25 all three answers
  (guided first run, Quick Show, the levels) are to be **built**, not
  chosen among. Its doc's own "Still open" list has shrunk to one real
  question (presets shared or separate between Quick Show and New Show…);
  status.md's older "Four questions" line was stale.
- **Windows of their own** — the built pop-outs (Slide Editor, the
  library panel, the Inspector, the Timeline pane) don't cover the whole
  original list: **the Library pane itself** (the sidebar, not the
  separate floating Library panel) and **the Browser** (Edit Show's file
  column) still can't detach. Answer 7 (double-click's meaning) is also
  still genuinely undecided — not superseded by the pop-out work.
- **Five Open Questions** in the feedback doc itself (greyed-transport
  drag target, glass/vibrancy in light mode, Show Similar's engine,
  large-library DB/indexing, the collections list column dropdown) —
  none buildable without Jason's call first.

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

- **The sort strip reads "Custom Order" in the plain Library.** The sort
  is shared with collections; the plain Library shows its files in the
  order they were added. The strip should name the sort actually in use.
  Deferred by Jason to another pass (2026-09-25).
- **`LibraryLocation.isInICloud` loops forever on a path containing
  `..`** (`ShowToolsCore/Library.swift:50`): `deleteLastPathComponent` on
  `..` never shortens the path. Hit with a test launch path
  `…/Library.sqlite/..`: the app hung at 100% CPU before opening a window,
  and needed `kill -9` (and its launch note cleared). Not fixed.
- **Undo registered outside an event stays invisible to Edit ▸ Undo
  until the next event** (AppKit's automatic group stays open). Fixed for
  drag-to-reorder by an explicit undo group; other paths that register
  undo from a `Task` or after an `await` haven't been checked.
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
