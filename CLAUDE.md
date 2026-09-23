# CLAUDE.md — ShowTools

A macOS slideshow composer and player for Jason's own Mac. The plan, with
every decision so far, is in `spec/plan.md`: read it first. The state of play
(what's built, what's confirmed by hand, what's next) is in `spec/handoff.md`.
Phase 5, BGTools (the desktop companion app that lives inside ShowTools),
has its own spec: `spec/bgtools.md`. Both app bundles are built by one
Xcode project, so BGTools is nested inside ShowTools: `spec/xcode-port.md`.

## Layout

- `Sources/ShowToolsCore/`: no UI. Models, the SQLite library, ingest, the
  timeline (`ShowTimeline.frame(at:)`), the `Compositor`, and setlist
  export (`Setlist`, `MetadataStrip`). Everything
  that draws a show goes through `frame(at:)` → `Compositor.compose`,
  including the future video exporter. Keep it that way.
- `Sources/ShowToolsPlayback/`: the player, shared with BGTools:
  `PlaybackEngine`, `ShowCanvas`/`ShowCanvasView`, `MediaProvider`,
  `MusicPlayer`. The engine reads shows and files through `ShowSource`
  (AppModel is one; BGTools' read-only reader will be another), never the
  app's types. Anything the app uses from here must be `public`.
- `BGTools/`: the desktop companion app (spec `spec/bgtools.md`) and its
  Control Center tiles (`BGTools/Controls`). Both are targets of the root
  `project.yml`, and the built BGTools is nested inside ShowTools at
  `Contents/Library/LoginItems/BGTools.app`.
  It opens libraries with `Library(readingOnly:)` only. Its settings and
  the show each mode builds are in `Sources/BGToolsCore` (tested). Test it
  with `open -n --env BGTOOLS_SETTINGS=<scratch settings.json> build/ShowTools.app/Contents/Library/LoginItems/BGTools.app`,
  the settings pointing at a scratch library (never the real one); it
  re-reads the file when it changes and logs to `~/Library/Logs/BGTools.log`.
  `BGTOOLS_OPEN_WINDOW=1` opens its window at launch, `BGTOOLS_OPEN_PANEL=1`
  its panel; `AXTOOL_APP=bgtools`
  lets axtool drive it.
- `Sources/ShowToolsApp/`: the SwiftUI/AppKit app. `PlaybackEngine` owns a
  show's clock, media and drawing, and any number of `ShowCanvas` views
  show it (the Edit Show preview and its pop-out share one engine). A paused
  engine stops drawing about 0.6s after the last change; call `touch()`
  after anything visible changes.
- Video export lives in Core (`MovieExport` settings and codecs,
  `MovieWriter` the one place that builds an `AVAssetWriter`,
  `MoviePictureTrack`, `MovieSoundTrack`/`MovieSoundRenderer`,
  `MovieMedia` the synchronous loader) with `MovieExportPanel` in the app.
  **Write one off the main thread**, and feed a writer whichever input
  will take data rather than waiting on the one that's behind — both
  orderings deadlock, and `spec/video-export.md` says how.
- App files worth knowing: `TransformOverlay` (the handles, arrow keys
  and Rotation mode on the preview), `StorylineView` (the timeline's rows,
  drawn in the show's own `rows` order, with their handles and drawers;
  the blocks and the lane's transitions row), `ImagesRow` (the lane's images row),
  `MusicRow` (songs and their waveforms; move, trim, overlaps),
  `LevelLine` (the level line on song and lane-image clips: volume or
  opacity, and the fades), `MusicPlayer` (plays the songs on
  AVAudioEngine and is the show's clock while it does; `PlaybackEngine.syncMusic`
  must follow anything that starts, stops or moves the clock), `Waveforms`
  (read once per file, cached in `<library>/Cache/Waveforms` by hash), `CollectionBrowser`
  (Edit Show's right column), `CollectionAdd` (the in-app drag type and the
  "add to collection?" question), `Libraries` (open/new/private),
  `Fingerprints` (Vision feature prints for Find Similar, cached in
  `<library>/Cache/Prints` by hash), `KeepOneSheet` (Keep One on a similar group), `FrameStrip`, `EffectsTimeline`, `EffectControls` (sliders, pads), `RhythmPanel`
  (the Rhythm tool: a floating panel, `RhythmTool.shared` holds its show,
  undo manager and ruler preview), `RhythmNotationView` (a pattern as notation:
  Bravura's glyph outlines in a `Canvas`, placed by `RhythmNotation.layout`), `RhythmGridView`
  (the drum-machine view, through `RhythmGrid`).
- `Resources/Fonts/`: Bravura, the SMuFL music font (SIL OFL 1.1, licence
  alongside). `make-app.sh` copies it into the app and `ATSApplicationFontsPath`
  loads it, so it only exists in the built app, not under `swift run`.
- `Sources/stcli/`: dev CLI. `ingest`, `show` (creates a show; it doesn't print one), `render` (writes frames
  through the Compositor to PNG, which is how transitions get checked by eye),
  `movie` (a real movie through the same path — video export,
  `spec/video-export.md`) and `mix` (just the show's music, rendered
  offline).
- `make-app.sh`: builds `build/ShowTools.app` with Xcode, through the root
  `project.yml` (XcodeGen; `ShowTools.xcodeproj` is generated and
  gitignored). One app holds everything: the tiles in `Contents/PlugIns`,
  BGTools in `Contents/Library/LoginItems`, Bravura in Resources. The
  libraries, `stcli` and the tests stay SwiftPM — `swift test` is
  unchanged. View ▸ Desktop Show… launches the nested BGTools and
  registers it at login (`SMAppService.loginItem`); deleting ShowTools
  takes all of it. `install.sh` copies the app to `~/Applications` and
  launches it once, which is the only way the Control Center tiles
  register — testing tiles means installing, not `build/ShowTools.app`.
  Caches lie: a new or renamed tile needs `CURRENT_PROJECT_VERSION`
  bumped and `killall chronod`.
- `tools/`: `make-test-library.sh <dir>` builds a scratch library with
  generated media and a test show. There are also a window lister and a
  contact-sheet tool, for checking screenshots.

## Rules

- **Never test against the real library** (`~/Pictures/ShowTools Library.noindex`).
  Set `SHOWTOOLS_LIBRARY=<scratch path>`: `open -n --env SHOWTOOLS_LIBRARY=… build/ShowTools.app`.
  A launch with any `SHOWTOOLS_` variable but no `SHOWTOOLS_LIBRARY` (a dev
  hook alone, or a typo) opens nothing and says why
  (`LibraryLocation.testLaunchProblem`). A test copy that crashes can be
  relaunched without its environment (the crash reporter's Reopen), so
  test launches leave a note that a proper quit removes, and the first plain
  launch after a crashed one opens nothing (`TestLaunchRecord`). Close test
  copies with `kill` or ⌘Q; `kill -9` leaves the note, costing one refused launch.
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
  (reorder, trim, Ken Burns) commit once, on release, so each is one undo step.
- Modifiers on a SwiftUI `Group` apply to every child. Use a `ZStack` when
  a container needs its own onAppear/onDisappear/task.
- Edit Show's columns are `ColumnsSplitView`, a manual NSSplitView layout.
  Don't switch back to NSSplitViewController or holding priorities: the
  lowest-priority column absorbs every divider drag (measured). Its dividers
  draw clear on purpose, because with a manual layout NSSplitView's divider
  layers go stale. Check AppKit layout in a standalone harness or with a
  layer-tree dump before changing it.
- Accessibility is granted to the Claude app (2026-09-21), so the app can
  be clicked, dragged and typed into: `tools/axtool.swift` reads the UI
  (`dump`, `find`, `menustate`) and acts with real events (`click`, `drag`,
  `type`, `key`, `menu`). Run hands-on checks with it, always on a scratch
  library, and keep them cheap: read with `find`/`dump` (text), and take a
  screenshot only when the check is about what's on screen. Cross-app drops
  (Finder, Photos), Touch ID, pinch, and look-and-feel still go on Jason's
  list. Don't drive the app while Jason is using it.
- Songs are library items of kind `.audio` and are never slides or lane
  images: anything that adds items to a show filters with `model.pictures`
  (or `model.songs` for the music row).
- The library item carries no slide settings. Settings belong to each use of
  it (`Slide`). The same file can appear many times with different settings.
- Settings JSON decodes field by field. Don't replace that with synthesized
  Codable: one unreadable field would reset all of them, and the next save
  would make the loss permanent. Every model type does this, including
  `Transition`, `KenBurns`, `Rotation`, `Transform` and `OverlayClip`, down to
  `KenBurnsFrame`, `ImagePoint` and `SRGBColor`. A new field on a synthesized
  type would drop every saved value that lacks it.
- Removing or renaming an enum case is the same trap. An unreadable enum
  field falls back to its default, but `Transition` requires its `style`:
  saved transitions of a removed style become the show's default (as
  Accordion's would have), permanently on the next save. `KenBurnsSetting`
  and `SlideLength` are synthesized enums, so a removed case drops the
  whole setting. Keep old cases decodable, or migrate them.
- Library schema changes are additive migrations (`Library.migrate`,
  currently version 12), each tested by opening a library written by the
  version before. The master library upgrades itself on first open, after
  copying its database to `Library.sqlite.v<N>.bak`. A new migration must
  also raise `Library.schemaVersion`, or that copy isn't made (the
  new-library test fails if they disagree).
- `MediaItem` is not called `LibraryItem`, and the app refers to
  `ShowToolsCore.Transition` by its full name, because both short names
  collide with SwiftUI. Likewise `SRGBColor` (not `RGBColor`, QuickDraw's)
  and `MediaCollection` (not `Collection`, Swift's).
- Measure, don't guess: write frame, hit-test or timing probes to a file in
  the scratchpad. `log show` returns nothing from this app in Claude's
  sandbox, so a "no log lines" check proves nothing. Remove probes before
  committing.
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
  commits, never one. `git status` first, stage everything related, and say
  what went in and what was deliberately left out. If in doubt about the
  rhythm, read `git log` — it shows the expected cadence better than any
  instruction here. **Offer the push in the closing line**, where Jason
  reads it: the working pattern is a reply that ends "commit and push,
  then do X". An ask at the top of a long reply scrolls past unseen.
- Tell Jason before restarting the app: he's often using it. (Until he has
  made a first real show there is nothing to disturb, so open and drive it
  freely on a scratch library.)
- Library delete conventions (Delete asks first, ⌘Delete moves to the Trash
  without asking) and the slide-removal notice are settled decisions. See
  the plan.
