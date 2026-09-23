# Phase 4 — setlist export and import (2026-09-22)

From `spec/handoff.md`, moved here unchanged on 2026-09-23 when that
file was retired. This is history: what happened, and when. It is not a
place to look up how the app works today — that is `spec/status.md`.

## Phase 4a: core export (2026-09-22)

- `Setlist.swift`: `SetlistManifest` (show.json, decoded field by field
  with lenient lists), `SetlistTSV` (text forms for every cell),
  `SetlistExport.plan` (reads the library, on its thread; fails with
  `missingFiles` before writing anything) and `SetlistExport.write`
  (off the main thread; builds a hidden sibling folder and moves it into
  place; replaces an earlier export of the same show via `discard`, the
  Trash by default; refuses any other non-empty folder).
- `MetadataStrip.swift`: measured before it was written (see the plan's
  Privacy bullet). Each stripped copy is read back; a failure falls back to
  an unstripped copy, listed in `Result.notStripped` for 4c to show.
  Songs keep their tags (Jason): only personal ones come off
  (`MetadataStrip.isPersonal`).
- `Library.identifier()`: a random id kept in `library_settings` (no
  schema change), so an export knows which library and show it came from.

## Phase 4b: core import (2026-09-22)

- `SetlistImport.swift`: `SetlistTSV.parse` and a parser for every cell
  form; `SetlistImport.read` (off the main thread: merges JSON and TSV,
  hashes the folder's files, collects problems), `filesToImport` (what the
  library lacks: library hash first, then the file's own) and `makeShow`
  (on the library's thread, after the app has imported those files; gives
  ratings and tags only to the items just imported; puts the show and all
  its files into the collection it's given).
- The app's part (4d): `read`, then its own import of `filesToImport`
  (which already dedupes by hash), then `makeShow` with the new item ids.
- `SlideSettings.kenBurnsSeed` (additive, field by field): the timeline
  seeds auto Ken Burns from it before `slide.id`. Import sets it to the
  exported id; Duplicate clears it on the copy, so copies still get their
  own move.

## Phase 4c: Export Show… (2026-09-22)

- `ExportPanel.swift`: File ▸ Export Show… (⇧⌘E; the show in the window,
  else the one selected in the sidebar). A Save panel names the folder;
  its accessory has "Hide from Spotlight" (on when the library is private)
  and a line saying whether metadata will be stripped. `SetlistExport.plan`
  runs on the main actor (a missing file is an alert pointing at Relink),
  `write` runs in a Task, and `ExportBanner` shows progress, then the
  result: Show in Finder, Done, and a Details menu listing any file that
  kept its metadata. The menu item is off while an export runs.
- Settings ▸ Export: "Strip metadata from exported files"
  (`exportStripsMetadata`, on unless set).
- Checked in the app on a scratch library (axtool): the menu item enabled,
  the panel's name and checkbox, Export writing all 11 test files
  (video, HEIC, GIF included) stripped with no warnings, the banner's
  text, and the Settings section. Not checked by hand: re-exporting over
  the earlier folder (it goes to the real Trash; covered by tests).
- A stale test-launch note from 2026-09-21 (pid 97389) was deleted from
  the real prefs at Jason's request.

## Phase 4d: Import Show… (2026-09-22)

- `ImportShowPanel.swift`: File ▸ Import Show… (no shortcut). A folder
  panel with "Make a collection for it" and a note naming the collection
  the show otherwise goes into. `AppModel.importShow` reads the folder off
  the main thread, imports what the library lacks through the ordinary
  `importFiles` (so the Import banner shows), then `makeShow`; new files
  are those not in `itemsByID` before. Problems go in one alert afterwards.
- File ▸ Import… gains "Make a collection for each folder".
- `newCollection(named:itemIDs:select:)` now takes a name and returns the id.
- Checked in the app on scratch libraries (axtool): import back into the
  exporting library (new "Test Show 2" in a new collection, no files
  copied, all 11 slides' settings identical with seeds = original ids,
  and defaults, rows, music, markers, editor state the same); import into
  an empty library (11 added, all in the collection); Import… with two
  folders (collections "Holiday Pics" and "Beach", from `Beach.noindex`).
- A new library already has an "Untitled Collection", so Import Show's
  "no collection yet" case (box forced on) practically never shows.

