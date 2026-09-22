# ShowTools — handoff, 2026-09-21 (end of day two)

For the next session. Read `CLAUDE.md` (rules) and `spec/plan.md` (every
decision, phase by phase) first. This file is the state of play. The repo
is `~/Projects/ShowTools`, pushed to **github.com/JasonHunt3r/jhg-showtools**
(public, `main`).

## Where it stands

| Phase | State |
|---|---|
| 1 Library + player | Built |
| 2 Composer (Edit Slides / Edit Show) | Built |
| **2a** Framing, rotation, match cuts | **Built**, except presets (Flush), which are deferred |
| **2b** Library manager | **Built** |
| **2c** The lane: transitions row + images row | **Built** |
| **3** Music + timeline | **Started 2026-09-21:** steps 1–5 of 7 built; **step 6 waits for macOS 27** (Apple's Music Understanding framework), and step 7 follows it (markers with M, snapping with N, the I/O range with ⌥X and ⌘L loop playback; modular rows; the music row, waveform, and playback on the music's clock; moving and trimming songs, crossfades, and the level line on song and image clips; the show as long as its longest row, with the show background after the last slide). Decisions and build order in `spec/plan.md` |
| 3b–5 | Not started |

Everything through 2b/2c is built, audited, and checked by hand (Jason and/or
Claude with `tools/axtool.swift`). The detailed build history for each phase
lives in git log and in memory (session AARs); this file only tracks what's
still open.

## Recently completed (2026-09-21, third session that day)

Picked up from small requests plus the rest of Phase 2b:
- **Inspector polish:** a header bar (icon, selection name/length, a
  circled-X close) like the collection list's; its two section headers
  (Transform, Effects) now pin to the top of the column while their content
  scrolls under them (`LazyVStack(pinnedViews: [.sectionHeaders])` in place
  of `Form`, which doesn't support pinning).
- **Library delete**, the Photos convention: Delete asks (naming how many
  shows use the file); ⌘Delete and a context-menu item skip the prompt;
  either way the file goes to the Trash, its slides *and lane images* are
  stripped from every show that had it, and ⌘Z restores all of it, file
  included.
- **Batch rename:** Finder's Rename Items modes (Replace Text, Add Text,
  Format with index/counter/date and a start number), live preview, from
  the grid's context menu or File ▸ Rename….
- **Info panel:** a floating panel (⌘I, or the grid's toolbar/context menu)
  following the grid's selection live. Read-only metadata read fresh from
  the file (dimensions, size, format, date, camera, lens, exposure, GPS);
  rating; tags (schema 6) added/removed for the whole selection at once,
  feeding the grid's search; a Settings toggle also writes them as Finder
  tags.
- **Relink by hash**, closing out 2b: File ▸ Relink Missing Files… finds a
  file Finder moved or renamed behind the app's back and points its row at
  the new location, matched by content hash.

Library schema is now **version 6** (5 library settings, 6 tags on items).
Every upgrade is additive and tested by opening the previous version.

**Recurring lesson, worth knowing before building anything else with a
`.sheet` or a floating panel:** a separate window's own `\.undoManager`
isn't the presenting window's, and even the *right* `UndoManager` passed in
isn't enough by itself — AppKit vends every window its own, and ⌘Z asks
whichever window is *key*. A panel is key right after you finish typing
into it, the normal moment to press ⌘Z. Both traps are written up in full,
with the fix, in `spec/macos_panels_guide.md` (in the sibling `jhg-cutcheck`
repo, shared across projects) and in memory.

Full detail on all of the above — what was checked by hand, exact bugs
found and fixed (a coordinate-math bug in relink caught by a test before it
reached the app; a thumbnail-retry bug found only by looking at the
screen) — is in git log (`832abb5`, `1d3f2f3`, `e072613`, `5bb0433`) and in
memory (session AAR).

## Still needs Jason's hands

Claude has checked almost everything reachable with `axtool` (mouse, keys,
menus). What's left needs real hardware or real judgement:
- **Cross-app drags:** dropping files from Finder and from Photos onto the
  storyline, the images row, the grid, a collection.
- **Touch ID / the Mac's password:** opening a private library, and the
  locked screen's Unlock.
- **Pinch:** the work area's zoom, and the storyline.
- **A second screen:** popping the preview out onto it.
- **Look and feel:** cursors per handle zone, whether the sticky headers and
  inspector bar read right, whether the lane's drags feel right now that
  they're fixed.
- **One confirmation:** a real ⌘Z with the Info panel itself focused, right
  after editing a tag (axtool's synthetic version of this specific case
  didn't reach Undo, even though the same undo works via the menu and via
  ⌘Z with the main window focused — see the gotcha above; likely a
  synthetic-event quirk, not a real bug, but worth one real keypress).

**Suggested next step before diving into Phase 3:** a hands-on pass with
Jason's own photos, in a separate library (File ▸ New Library…) so the
master isn't touched. It's also when the parked "image stickiness"
question (below) gets settled.

## Starting Phase 3: music + timeline

Per `spec/plan.md`:
- Add a song (File ▸ Import a track, or similar) and draw its waveform on
  a timeline under the storyline.
- Slides appear as blocks under the waveform; dragging a block's edge
  changes that slide's length (this already exists for the plain
  storyline — the waveform is a new ruler-like element alongside it, not a
  replacement).
- **Alignment aids:** markers dropped by hand while listening (a keystroke
  on the beat); slide edges snap to markers. Automatic beat detection is
  explicitly deferred ("may come later if the markers turn out to be a
  chore") — don't build it first.
- Scrubbing the timeline scrubs the show (the engine's clock already
  becomes the music's clock once a track is loaded — see `Timeline.swift`'s
  clock note — so this should mostly fall out of that).

Suggested first questions to raise with Jason before writing code (per
`feedback_ask_for_clarity`/`feedback_verify_mental_model` in memory —
restate the flow back before coding): where a track lives in the data model
(per-show, stored how), what the waveform is drawn from (decode once and
cache, or on the fly), and what a "marker" actually is (a time value only,
or does it carry anything else).

## How to work on it

```sh
swift test                                  # 93 core tests
./make-app.sh                               # → build/ShowTools.app
tools/make-test-library.sh /tmp/STTest      # scratch library + generated media
open -n --env SHOWTOOLS_LIBRARY=/tmp/STTest/TestLib.noindex build/ShowTools.app
```
- **Never** run against the real library. Always set `SHOWTOOLS_LIBRARY`.
- Dev hooks are listed in `CLAUDE.md` (show, slide, image, rotation mode, transition, lane image, play).
- Screenshots: `swiftc tools/list-windows.swift` gives window ids, then `screencapture -x -o -l <id>`. `tools/contact-sheet.swift` tiles a folder of PNGs.
- **Get click/type coordinates from `ax find`/`ax dump` (Accessibility), never by eyeballing a screenshot** — especially one resized with `sips`, whose pixels don't match real screen points. Screenshots are for looking, not measuring; this exact mistake mis-clicked tiles twice in one session.
- Frames: `stcli render <lib> <showID> 960x540 <outdir> <t>…` draws through the real Compositor, lane images included.
- Driving the app: `swiftc -O tools/axtool.swift -o <scratch>/ax`, then `ax front <pid>`, `ax find <pid> <text>`, `ax click x y`, `ax type …`, `ax menu <pid> File "Import…"`. It refuses input unless ShowTools is frontmost. Read the UI with `find`/`dump` before taking screenshots. Close test copies with `kill` or ⌘Q, not `kill -9`.
- Reading the menus through Accessibility validates every item, like opening them; that's how a past split-view crash surfaced. A crashed copy's crash dialog has a Reopen button: it launches without `SHOWTOOLS_LIBRARY` (refused once, by design).
- Don't shell out to `osascript`/Finder for anything `ls`/`sqlite3`/`xattr` can already answer — it can pop a real macOS permission dialog outside the app, which `axtool` correctly refuses to touch.
- **Tell Jason before restarting the app.** He often has it open and is trying things.

## Ask Jason later
- **Image stickiness (2c).** Once he has his own files as a test bed: should a lane image stay at its time on the clock, or move with the slide it starts over when slides are trimmed or reordered? For now it stays on the clock.

## Known issues / debts
- **The Edit Slides header bar overflows** (Jason, 2026-09-21: address later). It scrolls sideways, and at normal window widths Background, Loop and "Videos play in full" sit past its right edge, out of sight. Options: wrap to two lines, or move the overflow into a menu.
- **CPU** is about 33–37% while playing. This needs work before Phase 5's desktop mode.
- Memory is about 430 MB while playing.
- **Video:** it can't go in the lane yet. The frame strip shows a video's first frame. The onion skin skips video slides.
- The zoomed-out work area doesn't draw a lane image's overhang past the frame.
- Inspector sliders have no live preview while dragging; they update on release.
- Accordion was dropped, and Page Curl is offered as "Page Turn".

## Lessons (details in memory)
- **Driving the Mac's UI is driving Jason's Mac.** Events go to whatever is in front. axtool refuses unless ShowTools is frontmost, and refuses a crash-relaunch that dropped its scratch-library environment.
- **Synthetic clicks (and synthetic key events) aren't proof of a bug, or of a fix.** Settle a disagreement with a harness or, failing that, one real keypress/click from Jason.
- **Harnesses first for AppKit questions.** A ten-line standalone harness answers an AppKit behaviour question faster and more certainly than reasoning about it.
- **Test the tests.** A new test should be run against the old code first, and fail there.
- **When Jason reports breakage right after a layout change, that change is what he means.** Ask before fixing symptoms.
- **Measure with probes**, written to a file — `log show` returns nothing from this app in Claude's sandbox.
- **Swift decoding traps:** every model type saved as JSON decodes field by field, never synthesized `Codable` — one unreadable field would otherwise drop every saved value, permanently on the next save.
- **A separate window's `\.undoManager` isn't the presenting window's, and registering on the right one isn't enough — the *key* window's own `undoManager` is what ⌘Z asks.** See "Recently completed" above; full write-up in `spec/macos_panels_guide.md`.
