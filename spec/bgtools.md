# BGTools — the desktop companion app

Phase 5 of ShowTools (renamed 2026-09-22; it was "Live desktop"). This file
holds BGTools' decisions and measurements; `spec/plan.md` points here.
**Nothing of BGTools is built yet.** What exists is research and throwaway
test programs (`tools/desktop-probe`, `control-probe`, `library-probe`,
`login-probe`), which answer "will this work?".

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

## Measured (2026-09-22, macOS 27.0, one built-in display)

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
- **Reading the library while ShowTools writes** (`tools/library-probe`,
  scratch copy): a writer saving through `Library` (744 saves in 20 s)
  and two readers opening `Library.sqlite` with `SQLITE_OPEN_READONLY`,
  polling `PRAGMA data_version` every 50 ms, reading inside one
  `BEGIN`…`COMMIT`. 0 torn reads, 0 busy/locked, 0 undecodable; a save
  noticed within 15 ms median, 44 ms worst; the writer isn't slowed (765
  saves alone). The reader leaves `Library.sqlite` and `-wal` untouched
  and writes only `-shm`, SQLite's shared index (every WAL reader marks
  its place there).
- **Launch at login: under test.** Two ad-hoc-signed probes
  (`tools/login-probe`), one registered with `SMAppService.mainApp`
  (reported `enabled`), one started by a LaunchAgent; both enabled and
  allowed in Background Task Management. Result after Jason's next login
  in `~/Library/Logs/BGLoginProbe.log`. (Research: SMAppService is
  reported unreliable for ad-hoc-signed apps; a LaunchAgent always works.)

## BGTools' read path (from the measurements)

Open read-only (never `Library.init`, which migrates, and never
`identifier()`, which writes); check `user_version` and refuse a newer
schema than it knows; poll `data_version`; read each change in one read
transaction; decode with ShowToolsCore's types; skip files deleted under
it; follow the library when it moves (a bookmark; ShowTools tells it).

## Still to test

- **Launch at login** (result pending, above)
- **Power**: live Core Image drawing against a looping HEVC video, per
  monitor
- **Several monitors**: needs a second display plugged in; the desktop
  probe already makes a window per display and Space
- **A tile that changes BGTools**: URL scheme or distributed notification

## Open questions (to settle with Jason one at a time)

From the 2026-09-20 plan, still applying:
1. **Play modes per monitor (and Space)**: the show in order · the show
   shuffled · a random show · random from all files. Add **random from a
   collection** now that collections exist? Songs are never slides.
2. **"All same"**: every monitor plays the same thing; a random pick made
   once and mirrored. How does it combine with per-Space shows?
3. **Monitors coming and going**: remembered by id (decided); what does a
   monitor never seen before get?
4. **Videos and GIFs** can play (it's a real window); a setting limits
   the desktop to still images, to save power.
5. **Wallpaper fallback**: set the real system wallpaper per monitor
   (stills, no transitions). Or only "leave the last picture as the
   wallpaper when BGTools quits"?

New with BGTools:
6. **How ShowTools installs it**: BGTools inside ShowTools.app (a login
   item in `Contents/Library/LoginItems`, the usual pattern) or copied to
   `~/Applications` on first use? Updated with each ShowTools build?
7. **Sound**: silent (suggested), even for shows timed to music.
8. **Settings for random pictures** (not slides of any show): one set of
   desktop defaults (length, transition, Ken Burns, fit)?
9. **Power**: pause when the display sleeps or the screen locks;
   "Pause on battery"? (Occlusion isn't dependable, measured.)
10. **Which library**: the one ShowTools has open, or its own choice?
    What happens on a library switch?
11. **Private libraries**: the lock is only ShowTools' door; BGTools
    reading one at login walks past it. Never play one on the desktop, or
    BGTools asks for Touch ID itself?
12. **Clicks** go straight through to the desktop (measured working).
13. **Control Center tiles**: which ones (Open BGTools; Desktop Show
    on/off; Next picture?).

## Originally (2026-09-20)

Phase 5 was "Live desktop": one borderless window per monitor at desktop
level inside ShowTools itself, a four-way play mode per monitor plus "All
same", hot-plugged monitors, videos allowed with a stills-only setting,
and a real-wallpaper fallback. The idea of doing it inside ShowTools is
gone; the rest carries into the open questions above.
