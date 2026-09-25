# Layout — where everything lives

**Reference.** The file-by-file map of the codebase: which target owns
what, and the few structural rules that go with each. Rules live in
`CLAUDE.md`, current state in `spec/status.md`.

- `Sources/ShowToolsCore/`: no UI. Models, the SQLite library, ingest, the
  timeline (`ShowTimeline.frame(at:)`), the `Compositor`, and setlist
  export (`Setlist`, `MetadataStrip`). Everything
  that draws a show goes through `frame(at:)` → `Compositor.compose`,
  the video exporter included. Keep it that way.
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
  the show each mode builds are in `Sources/BGToolsCore` (tested). How to
  launch and drive it is in the `showtools-testing` skill.
- `PaneKit/` (top level): our own pane system, **for any Mac app**, as
  its own Swift package, depending on nothing in ShowTools
  (`spec/panekit.md`). `cd PaneKit && swift test` runs its tests;
  `swift run PaneHarness` runs its test app. **In active use by the app**
  since `spec/panekit.md` steps 2–3 (2026-09-24): a local package
  dependency in both `Package.swift` and `project.yml`. It's the main
  window's own split (library | detail | the timeline pane, full width
  under both), Edit Show's and Edit Slides' columns, and every pane's
  pop-out (the Slide Editor, the library panel, the Inspector, the
  Timeline window).
- `Sources/ShowToolsApp/`: the SwiftUI/AppKit app. `PlaybackEngine` owns a
  show's clock, media and drawing, and any number of `ShowCanvas` views
  show it (the Edit Show preview and its pop-out share one engine). A paused
  engine stops drawing about 0.6s after the last change; call `touch()`
  after anything visible changes.
- Video export lives in Core (`MovieExport` settings and codecs,
  `MovieWriter` the one place that builds an `AVAssetWriter`,
  `MoviePictureTrack`, `MovieSoundTrack`/`MovieSoundRenderer`,
  `MovieMedia` the synchronous loader, `MovieVideoFrames`/`MovieVideoSound`
  for video slides) with `MovieExportPanel` in the app.
  `VideoSlideTiming` decides which moment of a file a video slide shows,
  for the player and the exporter both — a slide held longer than its
  video loops it, which is easy to lose when touching either.
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
  Caches lie about tiles; the `showtools-testing` skill says how.
- `tools/`: `make-test-library.sh <dir>` builds a scratch library with
  generated media and a test show. There are also a window lister and a
  contact-sheet tool, for checking screenshots.

