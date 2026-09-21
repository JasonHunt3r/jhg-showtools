# CLAUDE.md — ShowTools

A macOS slideshow composer and player for Jason's own Mac. The plan, with
every decision so far, is in `spec/plan.md`: read it first. The state of play
(what's built, what's confirmed by hand, what's next) is in `spec/handoff.md`.

## Layout

- `Sources/ShowToolsCore/`: no UI. Models, the SQLite library, ingest, the
  timeline (`ShowTimeline.frame(at:)`), and the `Compositor`. Everything
  that draws a show goes through `frame(at:)` → `Compositor.compose`,
  including the future video exporter. Keep it that way.
- `Sources/ShowToolsApp/`: the SwiftUI/AppKit app. `PlaybackEngine` owns a
  show's clock, media and drawing, and any number of `ShowCanvas` views
  show it (the Edit Show preview and its pop-out share one engine). A paused
  engine stops drawing about 0.6s after the last change; call `touch()`
  after anything visible changes.
- `Sources/stcli/`: dev CLI. `ingest`, `show`, and `render` (writes frames
  through the Compositor to PNG, which is how transitions get checked by eye).
- `make-app.sh`: builds `build/ShowTools.app` (a SwiftPM binary wrapped in a
  bundle, the same approach as CutSim).
- `tools/`: `make-test-library.sh <dir>` builds a scratch library with
  generated media and a test show. There are also a window lister and a
  contact-sheet tool, for checking screenshots.

## Rules

- **Never test against the real library** (`~/Pictures/ShowTools Library.noindex`).
  Set `SHOWTOOLS_LIBRARY=<scratch path>`: `open -n --env SHOWTOOLS_LIBRARY=… build/ShowTools.app`.
- `SHOWTOOLS_DEV_PLAY="<showID>:<slideIndex>[:full]"` opens the player at
  launch, so it can be screenshotted without clicking (UI scripting isn't
  permitted on this Mac). `SHOWTOOLS_DEV_SHOW="<showID>[:<slideIndex>]"`
  selects a show (and a slide). `SHOWTOOLS_DEV_IMAGE=1` also selects that
  slide's image in the Edit Show preview, so its handles show
  (`SHOWTOOLS_DEV_IMAGE=rotation` shows its Rotation handles). The mode comes from the `editMode` default:
  `defaults write com.jhg.showtools editMode show`.
- Every show edit goes through a `ShowMutator` with an undo name. Drags
  (reorder, trim, Ken Burns) commit once, on release, so each is one undo step.
- Modifiers on a SwiftUI `Group` apply to every child. Use a `ZStack` when
  a container needs its own onAppear/onDisappear/task.
- Edit Show's columns are `ColumnsSplitView`, a manual NSSplitView layout.
  Don't switch back to NSSplitViewController or holding priorities: the
  lowest-priority column absorbs every divider drag (measured). Its dividers
  draw clear on purpose, because with a manual layout NSSplitView's divider
  layers go stale. Check AppKit layout in a standalone harness or with a
  layer-tree dump before changing it.
- Jason can't be asked to grant accessibility, so nothing here can be
  clicked or typed into. Anything that needs a drag or a key press goes on
  his hands-on list in the handoff.
- The library item carries no slide settings. Settings belong to each use of
  it (`Slide`). The same file can appear many times with different settings.
- Settings JSON decodes field by field. Don't replace that with synthesized
  Codable: one unreadable field would reset all of them, and the next save
  would make the loss permanent.
- `MediaItem` is not called `LibraryItem`, and the app refers to
  `ShowToolsCore.Transition` by its full name, because both short names
  collide with SwiftUI.
- Library delete conventions (Delete asks first, ⌘Delete moves to the Trash
  without asking) and the slide-removal notice are settled decisions. See
  the plan.
