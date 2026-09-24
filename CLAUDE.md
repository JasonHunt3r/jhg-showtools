# CLAUDE.md — ShowTools

A macOS slideshow composer and player for Jason's own Mac.

## The docs

| File | | What it is |
|---|---|---|
| `spec/status.md` | **current** | **Read first each session.** The state of play in the present tense: what's built, what's next, what needs his hands, known issues. Rewritten each session, not appended to. |
| `spec/how-we-design.md` | current | Why things are the way they are: the six pillars of a slideshow, perceptual efficiency, and each principle with the story that taught it. The kernel of a design manual. |
| `spec/plan.md` | current | Every decision, phase by phase, with its reasoning. Read before designing anything. |
| `spec/bgtools.md` | current | Phase 5, BGTools: the desktop companion app that lives inside ShowTools. |
| `spec/video-export.md` | current | Video export: the writer, the traps, the codecs. |
| `spec/video-audio.md` | current | A video slide's own sound. |
| `spec/xcode-port.md` | current | Why one Xcode project builds both bundles, and how. |
| `spec/edit-slides-inspector-port.md` | current | The fix for the layout-loop crash: ported Edit Slides' inspector off SwiftUI's `.inspector()`. |
| `spec/simple-things-fast.md` | current | Planned: making simple things fast — the first run, playing without building a show, and Basic / Advanced / "Bring it on!" levels. |
| `spec/windows.md` | current | Planned: areas of the main window in windows of their own, and editors for one thing (the Slide Editor, a row opened up). A vision with open questions, not a build plan. |
| `spec/conventions.md` | current | What each gesture, key, right-click, drop and Edit-menu item means everywhere: Built / Settled / Proposed / Open, plus a log of conventions found by use. Fixes build toward it. |
| `spec/hig-audit.md` | current | Expected Mac behaviour that was never built: the Edit menu, context menus, keyboard selection, Edit Slides vs Edit Show. Findings and fix batches. |
| `spec/anatomy.md` | reference | The screen's map: one name for each area, how areas nest, the picture's layers, and what selecting or changing one area does to the others. Use its names. |
| `spec/layout.md` | reference | The file-by-file map: which target owns what. Read before moving code between targets or adding a file. |
| `spec/first-run-brief.md` | reference | A brief for whoever builds the guided first run. Not a build plan. |
| `spec/history/` | **history** | Dated events. **Never read for current rules or current state** — only when the question is *why* something is the way it is. Start at its `README.md`. |

Each feature spec opens with a status block: Planned / Building / Built
<date>, and what's left.

Two skills load on demand: **`showtools-testing`** before launching any
test copy or doing a hands-on check, and **`showtools-gotchas`** before
debugging something unexpected or touching export, playback, undo or
migrations.

## Layout

The file-by-file map of the codebase — which target owns what, and the
structural rules that go with each — is **`spec/layout.md`**. Read it
before moving code between targets or adding a file to one.

## Rules

- **Never test against the real library** (`~/Pictures/ShowTools Library.noindex`).
  Set `SHOWTOOLS_LIBRARY=<scratch path>`: `open -n --env SHOWTOOLS_LIBRARY=… build/ShowTools.app`.
  A launch with any `SHOWTOOLS_` variable but no `SHOWTOOLS_LIBRARY` (a dev
  hook alone, or a typo) opens nothing and says why
  (`LibraryLocation.testLaunchProblem`). A test copy that crashes can be
  relaunched without its environment (the crash reporter's Reopen), so
  test launches leave a note that a proper quit removes, and the first plain
  launch after a crashed one opens nothing (`TestLaunchRecord`). Close test
  copies with `kill` or ⌘Q; `kill -9` leaves the note, and **the refused
  launch it costs is Jason's, not the next test copy's** — see below.
- **A test copy shares Jason's preferences domain** (`com.jhg.showtools`),
  even with a scratch library. So a crashed test copy's `TestLaunchRecord`
  note makes **his** app refuse to open: "Library problem", an empty
  window and a long scratch path, which reads as a broken library to
  someone who didn't write the safety net. It happened to him twice on
  2026-09-23. Test copies also overwrite his column widths and window
  frames. **After any test copy dies, check and clear
  `defaults read com.jhg.showtools runningTestLaunches`; capture his
  layout keys before a test session and restore them after.** The
  `showtools-testing` skill has the commands.
- `SHOWTOOLS_DEV_PLAY="<showID>:<slideIndex>[:full]"` opens the player at
  launch, so it can be screenshotted without clicking (UI scripting
  was once off-limits; they still save clicks). `SHOWTOOLS_DEV_SHOW="<showID>[:<slideIndex>]"`
  selects a show (and a slide). `SHOWTOOLS_DEV_IMAGE=1` also selects that
  slide's image in the Edit Show preview, so its handles show
  (`SHOWTOOLS_DEV_IMAGE=rotation` shows its Rotation handles).
  `SHOWTOOLS_DEV_TRANSITION=<slideIndex>` selects the transition into that
  slide in the storyline's lane; `SHOWTOOLS_DEV_OVERLAY=<n>` selects the
  lane's nth image. The mode comes from the `editMode` default:
  `defaults write com.jhg.showtools editMode show`.
- Every show edit goes through a `ShowMutator` with an undo name. Drags
  (reorder, trim, Pan and Zoom) commit once, on release, so each is one undo step.
- Modifiers on a SwiftUI `Group` apply to every child. Use a `ZStack` when
  a container needs its own onAppear/onDisappear/task.
- Edit Show's columns are `ColumnsSplitView`, a manual NSSplitView layout.
  Don't switch back to NSSplitViewController or holding priorities: the
  lowest-priority column absorbs every divider drag (measured). Its dividers
  draw clear on purpose, because with a manual layout NSSplitView's divider
  layers go stale. Check AppKit layout in a standalone harness or with a
  layer-tree dump before changing it.
- Accessibility is granted to the Claude app (2026-09-21), so the app can
  be clicked, dragged and typed into with `tools/axtool.swift`, always on a
  scratch library — the `showtools-testing` skill has the rules. **Don't
  drive the app while Jason is using it.** Cross-app drops (Finder,
  Photos), Touch ID, pinch and look-and-feel still go on his list.
- Audio files (library items of kind `.audio`) are never slides or lane
  images: anything that adds items to a show filters with `model.pictures`
  (or `model.songs` for the audio row).
- **"Audio" is the user-facing name** for the audio row and what's in it
  (an **audio clip**), settled 2026-09-24: a recording isn't a song. The
  code keeps its older names (`MusicRow`, `show.music`, `model.songs`,
  `selectedSong`), and **`TimelineRow.Kind.music` must keep its raw value
  `"music"`**, which is saved in every show's rows (the enum trap below).
  "Sound" means only a video slide's own sound.
- The library item carries no slide settings. Settings belong to each use of
  it (`Slide`). The same file can appear many times with different settings.
- Settings JSON decodes field by field. Don't replace that with synthesized
  Codable: one unreadable field would reset all of them, and the next save
  would make the loss permanent. Every model type does this, including
  `Transition`, `PanAndZoom`, `Rotation`, `Transform` and `OverlayClip`, down to
  `PanAndZoomFrame`, `ImagePoint` and `SRGBColor`. A new field on a synthesized
  type would drop every saved value that lacks it.
- Removing or renaming an enum case is the same trap. An unreadable enum
  field falls back to its default, but `Transition` requires its `style`:
  saved transitions of a removed style become the show's default (as
  Accordion's would have), permanently on the next save. `PanAndZoomSetting`
  and `SlideLength` are synthesized enums, so a removed case drops the
  whole setting. Keep old cases decodable, or migrate them.
- Library schema changes are additive migrations (`Library.migrate`,
  currently version 12), each tested by opening a library written by the
  version before. The master library upgrades itself on first open, after
  copying its database to `Library.sqlite.v<N>.bak`. A new migration must
  also raise `Library.schemaVersion`, or that copy isn't made (the
  new-library test fails if they disagree).
- **"Pan and Zoom" is the user-facing name**, settled 2026-09-22 and
  renamed everywhere 2026-09-23: the UI, the code, the slide-settings JSON
  keys and the setlist columns (`panAndZoom` / `panzoom_*`). Every show in
  the library was disposable test material, so no old spelling was kept
  readable.
- `MediaItem` is not called `LibraryItem`, and the app refers to
  `ShowToolsCore.Transition` by its full name, because both short names
  collide with SwiftUI. Likewise `SRGBColor` (not `RGBColor`, QuickDraw's)
  and `MediaCollection` (not `Collection`, Swift's).
- Measure, don't guess: write probes to a file in the scratchpad, and
  remove them before committing. `log show` returns nothing from this app
  in Claude's sandbox, so a "no log lines" check proves nothing.
- In a `List`, rows drag with `.itemProvider`, never `.onDrag`. `.onDrag`
  turns a click on the row's content into drag tracking, so the row won't
  select or double-click (only its empty edges do), and a drag carries one
  row, not the selection. Measured in a harness, 2026-09-21. (The Library
  grid isn't a List, and its tiles' `.onDrag` is fine.)
- SwiftUI hosting views hit-test all their content, clipped or not. Edit
  Show's columns use `ColumnHost`, which takes the mouse only inside its
  frame. Keep it, or content wider than its column steals the next column's
  clicks and scrolling.
- **Commit at each step, without being asked.** Jason treats commits as his
  safety net, so work doesn't sit in the working tree waiting for
  permission. One commit per plan step, per measurement that settles
  something, and per settled decision — the history is the model (B1–B7 is
  seven commits in forty minutes). Commit once a step builds, its tests
  pass and any hands-on check is done. Two unrelated pieces of work are two
  commits, never one. **When a step closes an item in a feature spec,
  update that spec's status block in the same commit.** `git status` first, stage everything related, and say
  what went in and what was deliberately left out. If in doubt about the
  rhythm, read `git log` — it shows the expected cadence better than any
  instruction here. **Offer the push in the closing line**, where Jason
  reads it: the working pattern is a reply that ends "commit and push,
  then do X". An ask at the top of a long reply scrolls past unseen.
- Tell Jason before restarting the app: he's often using it.
- Library delete conventions (Delete asks first, ⌘Delete moves to the Trash
  without asking) and the slide-removal notice are settled decisions. See
  the plan.
