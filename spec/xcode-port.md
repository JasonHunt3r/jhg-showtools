# Porting ShowTools' packaging to Xcode (planned 2026-09-22)

**Why.** Jason: BGTools shouldn't be orphaned when ShowTools is deleted —
one app should hold both. Measured the same day: a helper app nested in
`Contents/Library/LoginItems` runs, takes its `bgtools://` URLs, launches
from cold and can be registered at login, but **its own Control Center
tiles never register** (macOS registers an app's extensions only when that
app is itself registered at a scanned location — `~/Applications`,
`/Applications` — and has been launched; a nested app never is).

`tools/nest-probe` then proved the way round it, end to end:

- an **Xcode-built host app** carries the tile extension itself,
- the helper app sits nested in `Contents/Library/LoginItems`,
- the tile registers, and **a tile press reached the nested helper**
  (Jason pressed it; the helper had been quit and was launched by the
  system),
- `SMAppService.loginItem(identifier:)` registered the nested helper —
  Background Task Management lists it enabled and allowed.

ShowTools can't host tiles as it is, because it isn't an Xcode-built app:
it's a SwiftPM binary wrapped in a bundle by hand (`make-app.sh`), so its
embedded extension is never properly built or signed as one. Hence this
port.

## What the finished arrangement looks like

```
ShowTools.app                            (Xcode target, com.jhg.showtools)
  Contents/PlugIns/BGToolsControls.appex (com.jhg.showtools.bgcontrols)
  Contents/Library/LoginItems/BGTools.app(com.jhg.showtools.bgtools)
  Contents/Resources/Fonts/Bravura…
```

- The **package keeps everything real**: `ShowToolsCore`,
  `ShowToolsPlayback`, `BGToolsCore`, `stcli` and all the tests stay
  SwiftPM, built and tested with `swift test` as now. Only the two app
  bundles move to Xcode.
- Tiles open `bgtools://` URLs, which reach the nested BGTools, launching
  it if it's quit (measured).
- ShowTools registers BGTools at login with
  `SMAppService.loginItem(identifier: "com.jhg.showtools.bgtools")`.
- Deleting ShowTools takes BGTools, its tiles and its login item with it.

## Steps

- **P1 One project.** Extend `BGTools/project.yml` into a project at the
  repo root (`ShowTools.xcodeproj`, generated; keep it gitignored) with
  three targets: `ShowTools` (app), `BGTools` (app, nested by a copy phase
  into `Contents/Library/LoginItems`), `BGToolsControls` (extension, in
  ShowTools' PlugIns). Package products as dependencies, as BGTools does
  now. Sources stay where they are.
- **P2 ShowTools' bundle.** Carry over every Info.plist key `make-app.sh`
  writes: `ATSApplicationFontsPath` (Fonts), the exported drag type
  `com.jhg.showtools.items`, `LSMinimumSystemVersion`,
  `NSHighResolutionCapable`, `NSSupportsAutomaticTermination` false. Copy
  `Resources/Fonts` in. Unsandboxed, ad hoc signed, hardened runtime off
  (as now).
- **P3 Identities.** BGTools becomes `com.jhg.showtools.bgtools` and the
  extension `com.jhg.showtools.bgcontrols` (an extension's id must sit
  under its host's; the probe's did). Keep the `bgtools://` scheme and the
  tiles' `kind` strings, so nothing else changes. Note in the spec that
  BGTools' saved window position and login registration start fresh; its
  settings file (`~/Library/Application Support/BGTools/settings.json`)
  and the tiles' state file don't move.
- **P4 Installing.** Delete `BGToolsInstall`'s copying: View ▸ Desktop
  Show… now launches the nested BGTools and registers it at login.
  Remove `LoginItem.registerOnceIfInstalled` from BGTools (ShowTools owns
  that decision); keep the "Open at login" switch, which flips the same
  registration.
- **P5 Build scripts.** `make-app.sh` becomes a thin wrapper around
  `xcodebuild` producing `build/ShowTools.app` (and keeps its name, since
  CLAUDE.md and habits point at it). `BGTools/build.sh` goes away.
  `install.sh`: copy `build/ShowTools.app` to `~/Applications` and launch
  it once — tiles only register from there.
- **P6 Check it.** `swift test` (175 + 12) unchanged; then by hand:
  ShowTools opens a scratch library, plays a show, the fonts are there
  (Rhythm panel notation), a drag from the Collection Browser still works;
  BGTools plays on each Space, its window and panel open, both tiles
  appear and work, and login registration shows in System Settings.
- **P7 Tidy.** Remove `~/Applications/BGTools.app` and the old tiles,
  `tools/nest-probe/remove.sh`, and update CLAUDE.md (build, install and
  test commands) and the handoff.

## Risks, from today's experience

- **Caches lie.** New or renamed tiles need a build-number bump and
  `killall chronod`, and LaunchServices may need `lsregister -f`. Two
  rounds were lost to this today; expect it, don't debug it.
- **Signing order.** Three nested pieces, ad hoc: the extension and the
  nested app must be signed before the outer app. XcodeGen did this in
  the probe, but ShowTools is bigger.
- **Tiles need an installed copy.** Testing them means `install.sh`, not
  `build/ShowTools.app`. The library rule doesn't change: test launches
  still set `SHOWTOOLS_LIBRARY` to a scratch library, and BGTools still
  takes `BGTOOLS_SETTINGS`.
- **Keep the working build.** Don't delete the current
  `~/Applications/BGTools.app` or its tiles until the new arrangement
  plays a show, opens the panel and shows both tiles.

## Not part of this port

Jason's hands-on pass on BGTools (private unlock, the panel closing on a
click elsewhere, Space-switch pausing), the Ken Burns cost (~40% of a core
while it moves), telling BGTools when a library moves, and video export
(the plan's "Later"; the render hook is built in).

## Done, 2026-09-22 (fourth session)

All of P1–P7, in one pass. The project built on the first try and every
check passed.

- **The project** is `project.yml` at the repo root (`ShowTools.xcodeproj`
  generated, gitignored), three targets, deployment target 14.0 for
  ShowTools and 26.0 for BGTools and the tiles. XcodeGen signed the three
  nested pieces in the right order without help; nothing had to be done
  about signing order after all.
- **Identities** are as planned: `com.jhg.showtools`,
  `com.jhg.showtools.bgtools`, `com.jhg.showtools.bgcontrols`. The tiles'
  `kind` strings are unchanged.
- **P4** `BGToolsInstall.swift` became `BGToolsHelper.swift`: no copying,
  no `isInstalled`, so the menu item is plain "Desktop Show…". It
  launches the nested BGTools and calls `registerAtLogin`.
  BGTools' `LoginItem` lost `registerOnceIfInstalled` and now uses
  `SMAppService.loginItem(identifier:)`, not `.mainApp` — a nested app
  can't register itself as `mainApp`, and its "Open at login" switch must
  flip the registration ShowTools made.
- **P5** `install.sh` passes `SHOWTOOLS_LIBRARY` through to the launch
  when it's set, so the script itself can be checked without opening the
  real library.

### Measured

- `swift test`: 175 + 12, unchanged.
- The app opens a scratch library, plays a show, and Bravura renders in
  the Rhythm panel — `ATSApplicationFontsPath` works in an Xcode bundle.
- Installed copy → Desktop Show… → the nested BGTools launched, took
  `bgtools://window` and opened its window. Background Task Management
  lists `com.jhg.showtools.bgtools` **enabled, allowed**, with parent
  `com.jhg.showtools`.
- `pluginkit` lists `com.jhg.showtools.bgcontrols` from
  `~/Applications/ShowTools.app`; **Jason confirmed both tiles work in
  Control Center**.

### Taken out (P7)

`~/Applications/BGTools.app` (to the Trash) with its tiles, the nest
probe, and the control probe's build products; `BGTools/build.sh` and
`BGTools/project.yml`. `pluginkit` now lists one tile extension, the new
one. The probes' sources stay in `tools/`, as the record of what was
measured.

Left behind: stale Background Task Management entries for
`com.jhg.bgtools` and the two `com.jhg.nestprobe` ids, whose bundles are
gone. `sfltool resetbtm` would clear them but resets every app's login
items, so they're left for macOS to prune, or for Jason to remove in
System Settings ▸ General ▸ Login Items.
