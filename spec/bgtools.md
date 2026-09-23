# BGTools — the desktop companion app

**Status:** Built 2026-09-22 (B1–B7). **Left:** Jason's hands-on pass
(private unlock with Touch ID, the panel closing on a click elsewhere,
Space-switch pausing, none re-done against the nested BGTools); the Pan
and Zoom cost; telling BGTools when a library moves.

Phase 5 of ShowTools (renamed 2026-09-22; it was "Live desktop"). This file
holds BGTools' decisions and measurements; `spec/plan.md` points here. It
began as research and throwaway test programs (`tools/desktop-probe`,
`control-probe`, `library-probe`, `login-probe`) answering "will this
work?" — they did, and it was built.

## What it is

A small companion app that plays ShowTools shows **as the desktop picture**
on each monitor: behind the desktop icons, on every Space, all day, at
little cost. It never edits anything.

Why a separate app (Jason, 2026-09-22): ShowTools has become a heavy
editor (database, undo, timeline, Rhythm tool), too much to keep running
all day for the desktop. BGTools is menu-bar-only (no Dock icon, no
editor), built in this repo on ShowToolsCore's renderer (`frame(at:)` →
`Compositor`), so a show looks the same on the desktop as in the editor.

## Decisions

- **ShowTools installs BGTools** (Jason, 2026-09-22): it ships as
  ShowTools' companion, not as a separate download. *How* is open (below).
- **BGTools reads the library itself, read-only** (Jason: "why couldn't
  the menubar extension also use and access the library?"), rather than
  being sent packages. Edits show up by themselves, and random from a
  collection or the library can work.
- **Control Center opens BGTools' window**; its **menu bar icon is
  optional**, a checkbox in its settings (Jason's menu bar is crowded).
  Control Center tiles can only be a button or a toggle, so the tiles
  open the window and perhaps switch the desktop show on and off; the full
  settings live in the window.
- **Shows per monitor and per Space**, and monitors are remembered by
  their own id, so a display plugged back in gets its setting back.
- If a macOS update breaks the unofficial Space calls (below), fall back
  to one window on every Space.

## Measured (2026-09-22, macOS 27.0; built-in display, then a 5K PA279CRV)

- **A window beneath the desktop icons** (`tools/desktop-probe`): at the
  desktop window level it sits one layer above macOS's wallpaper and below
  Finder's icons (window list, and a ScreenCaptureKit capture of just
  those layers). Ignoring the mouse, it "behaves as if it's wallpaper"
  (Jason: clicks, click-to-reveal, Spaces all fine).
- **Per Space** (`desktop-probe --per-space`): Spaces have no public
  identity. The unofficial CoreGraphics calls yabai and Hammerspoon use
  (`CGSCopyManagedDisplaySpaces`, `CGSAddWindowsToSpaces`…) exist on
  macOS 27.0; they list each display's Spaces with a lasting uuid (empty
  for the first desktop, so key that one as "desktop 1 of that display")
  and put a window on one Space only. Three desktops each showed their own
  window and colour (Jason). Displays have their own UUID.
- **Several monitors** (desktop probe, a 5K PA279CRV plugged into the
  laptop, "Displays have separate Spaces" on): plugging in, unplugging,
  plugging back in and adding a Space on the external display were each
  noticed within a second, and each window came up on its own display and
  Space with the right label and colour (Jason). Found on the way:
  - **Key Spaces by uuid, never by id.** After a replug the external
    display's first Space went from id 19 to id 23; its uuid
    (`E653A497…`) and the display's uuid stayed the same. Only the
    *main* display's first desktop has an empty uuid; the external's first
    Space had one.
  - **One change fires two or three notices** (screens changed ×2 plus
    spaces changed, same second). BGTools must wait a moment and rebuild
    once, or a slide show restarts three times per plug.
  - **Unplugging moves a display's Spaces onto the one left**, uuid and
    all (the external's Space 2 turned up as the laptop's fourth desktop),
    so a Space's setting follows it there.
  - The first probe run coloured windows by Space number, so both
    displays' Space 1 matched and Jason read it as a failure; test colours
    must differ across every window, not per display.
- **Occlusion** flickers "hidden" for under a second on every Space
  switch, and stayed "visible" under windows covering the screen, so
  pausing when hidden needs a delay and isn't a dependable power saver.
- **Control Center tiles work unsigned** (`tools/control-probe`): a
  WidgetKit extension, generated with XcodeGen and built by Xcode 27,
  signed ad hoc (this Mac has no certificate), installed in
  `~/Applications` and launched once. Both tiles ("Open BGTools", a
  button; "Desktop Show", a toggle) appeared in Control Center's gallery,
  could go in Control Center or the menu bar, and the button opened the
  app (Jason). The action ran in the sandboxed extension, not the app, so
  a tile that must change something in BGTools needs a way to reach it:
  App Groups want a certificate, so try a URL scheme (`bgtools://…`) or a
  distributed notification. (MacStories documented a Tahoe bug hiding
  third-party controls until the widget gallery is opened.)
- **A tile can change BGTools without opening it** (`tools/control-probe`,
  tiles Colour A/B/C, Jason pressing them, 2026-09-22). A tile's action
  always runs in the sandboxed extension, even when the same intent is
  compiled into the app too (C: logged by the extension, never reached
  the app). Two ways across both worked, every press, within the second:
  - **A, a distributed notification** (name only; a sandboxed sender
    gets no userInfo): reaches BGTools only if it's already running.
  - **B, a URL** (`bgtools://…`) opened with `activates = false` and
    handled in the app delegate's `application(_:open:)`, not SwiftUI's
    `onOpenURL` (which opens a window): with the app running it stays
    behind other windows; **with it quit, the press launches it, delivers
    the URL and changes it, all behind Jason's windows**. So tiles use
    URLs.
  - New tiles didn't appear in Control Center's gallery until the build
    number went up and `chronod` was restarted (`killall chronod`).
- **Reading the library while ShowTools writes** (`tools/library-probe`,
  scratch copy): a writer saving through `Library` (744 saves in 20 s)
  and two readers opening `Library.sqlite` with `SQLITE_OPEN_READONLY`,
  polling `PRAGMA data_version` every 50 ms, reading inside one
  `BEGIN`…`COMMIT`. 0 torn reads, 0 busy/locked, 0 undecodable; a save
  noticed within 15 ms median, 44 ms worst; the writer isn't slowed (765
  saves alone). The reader leaves `Library.sqlite` and `-wal` untouched
  and writes only `-shm`, SQLite's shared index (every WAL reader marks
  its place there).
- **Launch at login: both ways work, ad hoc signed** (measured
  2026-09-22). After Jason's logout and login at 12:44Z, both probes
  logged `LAUNCHED` in the same second, parent pid 1 (launchd): the one
  registered with `SMAppService.mainApp` and the one a LaunchAgent starts
  (`--from-launchagent`). So the reported unreliability of SMAppService for
  ad-hoc-signed apps didn't show on macOS 27.0; SMAppService is the
  Apple-recommended way and shows in Login Items with a switch. Probes
  removed afterwards (`tools/login-probe/remove.sh`).

## BGTools' read path (from the measurements)

Open read-only (never `Library.init`, which migrates, and never
`identifier()`, which writes); check `user_version` and refuse a newer
schema than it knows; poll `data_version`; read each change in one read
transaction; decode with ShowToolsCore's types; skip files deleted under
it; follow the library when it moves (a bookmark; ShowTools tells it).

## Still to test

- **Power** (a curiosity, not a gate; Jason: BGTools may do both live
  drawing and video): live Core Image drawing against a looping HEVC
  video, per monitor

## Settled (with Jason, one at a time)

These were the open questions. All thirteen are answered; the wording is
as it was when each was settled.

From the 2026-09-20 plan, still applying:
1. **Play modes** — **Settled (Jason, 2026-09-22): all five**, per monitor
   and Space: a show in order · a show shuffled · random from a
   collection · a random show · random from all files. Songs are never
   slides.
2. **"All same"** — **Settled (Jason, 2026-09-22): one switch overrides
   all.** On, one choice plays on every monitor and every Space, in sync
   (the same slide at the same moment). Off, each monitor's and Space's own
   settings come back; they're kept while it's on.
3. **Monitors coming and going** — **Settled (Jason, 2026-09-22):** a
   **"new screens" default** in BGTools (e.g. Random from all files, or a
   chosen collection) plays on any monitor or Space it hasn't seen; after
   that it's remembered by id (monitors) and uuid (Spaces).
4. **Videos and GIFs** — **Settled (Jason, 2026-09-22):** they play;
   **"Stills only" is part of each monitor's and Space's setting** (video
   on one display, stills on another). With it on, a show skips its video
   and GIF slides.
5. **Wallpaper fallback** — **Settled (Jason, 2026-09-22): never touch
   it.** BGTools never changes the system wallpaper; when it stops,
   whatever Jason had shows through.

New with BGTools:
6. **How ShowTools installs it** — **Settled (Jason, 2026-09-22): copy to
   `~/Applications`.** ShowTools carries BGTools inside it and copies it
   out the first time the desktop is turned on, replacing the copy when a
   newer build arrives. A normal, visible app (where tiles were measured
   to load); deleting ShowTools leaves it behind.
7. **Sound** — **Settled (Jason, 2026-09-22): silent, with a switch** in
   each monitor's and Space's setting that lets its show's music (and
   video sound) play. Detail for the build: if two screens have it on,
   only one should be heard (the one on the main display?).
8. **Settings for random pictures** — **Settled (Jason, 2026-09-22): one
   set of desktop defaults** in BGTools (length, transition, Pan and Zoom
   on/off, fit or fill), used by every random mode on every screen.
9. **Power** — **Settled (Jason, 2026-09-22): pause when** the display
   sleeps or the screen locks (always), in **Low Power Mode**, and when an
   app is **full screen on that display**. Not on battery as such. (A
   full-screen app is its own Space, so this falls out of pausing every
   window whose Space isn't the active one on its display, which saves
   the hidden Spaces too; resume where it left off.)
10. **Which library** — **Settled (Jason, 2026-09-22): per monitor and
    Space.** Each monitor's and Space's setting names its own library,
    starting with the one ShowTools has open. A library switch in
    ShowTools doesn't change the desktop.
11. **Private libraries** — **Settled (Jason, 2026-09-22): Touch ID when
    one is chosen; back to public on sleep or lock.** Choosing a private
    library for a screen asks for Touch ID (BGTools' own prompt). When the
    Mac sleeps or the screen locks, every screen playing a private library
    drops it and goes back to its last public setting (or the "new
    screens" default), so it isn't there when the lid opens (Jason: "we
    don't want to forget we've got a racy BG running the next time we open
    the lid"). The switch happens on the sleep/lock notice, before the
    screen can be seen again; a private choice is never restored at
    launch.
12. **Clicks** — **Settled:** they go straight through to the desktop
    (measured working).
13. **Control Center tiles** — **Settled (Jason, 2026-09-22): Open BGTools
    and Desktop Show on/off.** Control Center only holds buttons and
    switches (macOS 27 SDK: `ControlWidgetButton`, `ControlWidgetToggle`,
    optionally configured when added, a status line, draggable to the
    menu bar), so "something bigger" is **BGTools' panel**: the Open tile
    drops a compact floating panel near the top right, a row per monitor
    and Space (thumbnail, mode and show, Next, Stills only) plus All same.
    Favourite "Play X on screen Y" tiles can come later.

## Build steps (proposed 2026-09-22)

- **B1 Shared player. BUILT 2026-09-22** (172 tests pass; Edit Show's
  preview and the player checked in-app on a scratch library). Move `PlaybackClock`, `PlaybackEngine`,
  `MediaProvider`/`VideoSlot`, `MusicPlayer` and `ShowCanvas` out of the
  app into a new SwiftPM library, `ShowToolsPlayback`. The engine talks to
  a small `ShowSource` protocol (a show by id, its timeline, an item's
  URL, editing state) instead of `AppModel`; AppModel conforms. ShowTools
  behaves exactly as before, so the desktop draws shows exactly as the
  player does (the Compositor rule).
- **B2 BGTools skeleton. BUILT 2026-09-22** (then `BGTools/build.sh`;
  since the Xcode port it's a target of the root `project.yml` and is
  built, nested, by `./make-app.sh` — `spec/xcode-port.md`;
  `Library(readingOnly:)` + 3 tests; played the test show on 4 Spaces and
  noticed a save within the second). `BGTools/` (XcodeGen: the app, later its
  Control Center extension) using the package. A read-only library reader
  in ShowToolsCore (the read path above) that is a `ShowSource`. Desktop
  windows per display and Space (uuid keys, one rebuild per burst of
  notices) playing one show from `BGTOOLS_LIBRARY` (a scratch library;
  never the real one in tests).
- **B3 Settings and modes. BUILT 2026-09-22** (`BGToolsCore`:
  `DesktopSettings`, `DesktopShow`; 12 tests. In the app a `Player` per
  screen, one for all under All same; checked on 4 Spaces with a test
  settings file: every mode, Stills only, All same in sync and back,
  re-picks each pass). No UI yet: the settings file
  (`~/Library/Application Support/BGTools/settings.json`, or
  `BGTOOLS_SETTINGS`) is read, and re-read when it changes. Found: hidden
  Spaces keep drawing (B6 pauses them); a new pick must restart the engine
  from the top (`restartWithLatest`), since keeping the place by slide id
  lands anywhere when slide ids are item ids. Each monitor's and Space's setting (library,
  mode, show or collection, Stills only, sound), All same, the "new
  screens" default, the desktop defaults; random modes build a show on the
  fly with those defaults.
- **B4a The window. BUILT 2026-09-22** (Jason asked for a larger, regular
  window alongside the panel, opened from it). Monitors drawn as arranged
  plus a list of each one's Spaces on the left; the selected screen's
  live preview (⏮ ⏯ ⏭, "Show · n of N") and its setting on the right
  (library, the five modes, a thumbnail grid of shows or collections,
  Stills only, Sound); All same (switch in its row), New screens and
  Random pictures below. Desktop Show switch in the toolbar. Opens with
  `bgtools://window`, by opening BGTools again, or `BGTOOLS_OPEN_WINDOW=1`;
  BGTools shows in the Dock only while it's open. Libraries on offer:
  ShowTools' main and recent ones (its prefs, read only), or in a test
  launch only those the settings name. Checked by driving it with axtool
  (`AXTOOL_APP=bgtools`) on the test settings. Private libraries show a
  note until B6.
- **B4b The panel. BUILT 2026-09-22.** A borderless, non-activating
  panel with the popover blur, at the top right of the screen the pointer
  is on, sized by its content and kept in the corner. A row per Space (live
  thumbnail, current one outlined, what it plays; ▾ picks a show,
  shuffled show, collection, random show or all files; ⏭ next; ⚙ Stills
  only, Sound, "Open in BGTools…"), All same collapsing them into one;
  New screens (a menu), Random pictures (→ window), "Open BGTools…".
  `bgtools://open` toggles it (tested); Escape closes it (tested); a
  click anywhere else closes it (a global mouse monitor: for Jason to
  try). Was: `bgtools://open` shows it without activating other
  windows; rows per monitor and Space.
- **B5 Control Center. BUILT 2026-09-22** (Jason pressed all four:
  both tiles, both ways). `BGTools/Controls` is a widget extension with
  **Open BGTools** (→ `bgtools://open`, the panel) and **Desktop Show**
  (→ `bgtools://show/on|off`), each opened without activating BGTools,
  which also launches it if it's quit. The tile is sandboxed and can't
  read the settings, so BGTools writes `control-state.json` beside them
  and calls `ControlCenter.shared.reloadControls`; the extension has a
  **read-only sandbox exception** for `~/Library/Application Support/BGTools/`
  alone, which works ad hoc signed (measured). New tiles need a build
  number bump and `killall chronod` before Control Center lists them.
  The probe app and its tiles are gone; BGTools is installed in
  `~/Applications` (where tiles load from).
- **B6 Pausing and private libraries. BUILT 2026-09-22.** A player pauses
  unless one of its screens is the Space its display is showing, and
  everything pauses when the Mac or its displays sleep, the screen locks
  (`com.apple.screenIsLocked`, the old distributed notification: there's no
  public one) or Low Power Mode is on. A private library needs Touch ID in
  BGTools' window ("Unlock…"); until then that screen plays its last
  public setting, or the "new screens" default (checked: it fell back at
  launch). Sleep or lock clears every unlock, and none is restored at
  launch.
  **Power, measured on the way** (the "curiosity" that turned out to
  matter): one desktop window redrawing cost **40% of a core even on a
  motionless still**, because every frame was recomposed. Now
  `FrameState.isMotionless` (a still picture, no transition, no Pan and Zoom,
  no lane image) lets a view skip frames until the slide changes: **40% →
  ~2%**. The desktop also draws at 30 fps rather than 60
  (`makeView(fps:)`), worth about 7 points on its own. **Pan and Zoom still
  costs ~40%**, since it really does move every frame — worth a look. It's
  why the random-mode default was flipped from `.auto` to `.off`
  2026-09-23: it's opt-in now, not a cost every random desktop show pays.
- **B7 ShowTools installs it. BUILT 2026-09-22.** `make-app.sh` builds
  BGTools (when XcodeGen is there) into `ShowTools.app/Contents/Resources`.
  **View ▸ Desktop Show…** (or "Set Up Desktop Show…" the first time)
  copies it to `~/Applications` and opens its window; it replaces the copy
  when the carried one is a different version **or newer** (versions rarely
  change while it's being built), quitting a running BGTools first and
  swapping the bundle whole. BGTools registers itself at login on its first
  run from `~/Applications` (`SMAppService.mainApp`), with an "Open at
  login" switch in its window's ⋯ menu. Checked end to end: the menu item
  installed it, it launched, registered, and opened its window. A screen
  with nothing chosen now gets **no window at all** (it was black before),
  so the normal wallpaper shows.
  **Left open:** telling BGTools when a library moves. Until then a moved
  library reads as "can't be opened" and is chosen again by hand.

## Originally (2026-09-20)

Phase 5 was "Live desktop": one borderless window per monitor at desktop
level inside ShowTools itself, a four-way play mode per monitor plus "All
same", hot-plugged monitors, videos allowed with a stills-only setting,
and a real-wallpaper fallback. The idea of doing it inside ShowTools is
gone; the rest carries into the open questions above.
