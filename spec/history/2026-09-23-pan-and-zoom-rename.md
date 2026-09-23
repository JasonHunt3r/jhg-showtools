# Ken Burns → Pan and Zoom, done, and the export it broke (2026-09-23)

The rename was settled 2026-09-22 (`spec/plan.md`, "Pan and Zoom, and a
simple way in") but not carried out: the docs changed, nothing else did.
Today it was.

## The rename

One pass, 168 references across 22 files: the UI, the code (`KenBurns*`
→ `PanAndZoom*` types and properties, `KenBurnsEditor.swift` →
`PanAndZoomEditor.swift`), the slide-settings JSON keys (`kenBurns` →
`panAndZoom`, `kenBurnsSeed` → `panAndZoomSeed` — synthesized from the
property names, so the rename alone moved them) and the setlist TSV
columns (`kenburns_start`/`kenburns_end`/`default_kenburns` →
`panzoom_start`/`panzoom_end`/`default_panzoom`). Every show in the
library was disposable test material, so no old spelling was kept
decodable — no `CodingKeys` shim, no TSV reader taking both names.
`spec/history/` was left alone on purpose: it is a dated record of what
was true on its day, and "Ken Burns" was the name that day.

While confirming the show-level default (`ShowDefaults.panAndZoom`) was
already `.off`, per Phase 2a's settled decision that an effect isn't a
slide's default state — BGTools' `DesktopSettings.startingRandomDefaults`
turned out to be the one place still setting `.auto`. It's also the one
default that measurably costs CPU: Pan and Zoom redraws every frame, about
40% of a core (`spec/bgtools.md`). Flipped to `.off` the same commit
(`8db7ffc`). `swift test`: 279 tests, all pass.

A second pass (`a0be113`) caught what the first search missed by only
covering `.swift` and `.md`: three shell scripts —
`tools/make-test-library.sh`, `make-demo-show.sh`, `add-demo-show.sh` —
write slide-settings JSON straight into the database with `sqlite3` or a
`add` helper, and still used the old `kenBurns` key. Not a crash:
`SlideSettings` decodes field by field, so an unrecognized key is just
ignored. The scripts would have kept running and quietly stopped setting
Pan and Zoom on every test and demo show.

## The installed app was stale

`~/Applications/ShowTools.app` had been built at 00:12, before the rename
commit (01:38) — so after the code was fixed, the app Jason had open
still said "Ken Burns" everywhere. Quit (he was using it — asked and told
first), `./make-app.sh`, `strings` on the new binary confirmed zero "Ken
Burns" left and the new copy in place ("Change Default Pan and Zoom",
"Edit Pan and Zoom", …), then `./install.sh`.

## The breakage test

Before the rebuild, Jason exported a movie and a setlist folder ("Trucks
to the Future", `~/Desktop`) from a show with Pan and Zoom on four of its
seven slides — on purpose, to see what the rename would do to it.

Its `show.tsv` header still reads `kenburns_start`/`kenburns_end`, and
`show.json` still has the `kenBurns` key, both written by the old binary.
`SetlistImport.read`, run against a scratch library (never the real one)
by way of a temporary probe added to `SetlistImportTests.swift`, run with
`swift test --filter`, then reverted:

```
problems: []
defaults.panAndZoom: off
001_...png panAndZoom: nil
002_...png panAndZoom: nil   (was "auto" in the export)
003_...png panAndZoom: nil   (was "auto")
...
006_...png panAndZoom: nil   (was "auto")
007_...png panAndZoom: nil   (was "auto")
```

Every slide came back with `panAndZoom: nil`, and `problems` was empty —
no warning reaches the import panel. `SetlistImport.mergeSlides` looks
up `row["panzoom_start"]`, which isn't in this file's header, so the
per-slide branch is skipped entirely; the JSON path is silently dropped
the same way, one field at a time. Confirmed the predicted breakage
exactly: an old export doesn't error, it just loses the setting.

**No backward-compat reader was added.** Not asked for, and the decision
already on record (above) was to accept the loss rather than keep the old
spelling decodable. Any setlist folder or `show.json` exported before
2026-09-23 will lose Pan and Zoom the same way if it's re-imported now.
