# ShowTools — status

**Read this first each session.** The state of play, in the present tense.
Rules are in `CLAUDE.md`, decisions in `spec/plan.md`, and what happened on
which day in `spec/history/` (never read for current rules). This file is
rewritten, not appended to: if a line has a date and a story, it belongs in
`history/`.

Repo: `~/Projects/ShowTools`, pushed to **github.com/JasonHunt3r/jhg-showtools**
(public, `main`).

## Where it stands

**Everything planned is built**, including Groups inside collections and
the range package (below). Phases 1–5, Phase 3b, Phase 4 and video
export. **318 tests** (306 core + 12 BGTools). **Library schema 13.**

| Phase | State |
|---|---|
| 1 Library + player | Built |
| 2 Composer (Edit Slides / Edit Show) | Built |
| 2a Framing, rotation, match cuts | Built, except presets (Flush), deferred |
| 2b Library manager | Built |
| 2c The lane: transitions row + images row | Built |
| 3 Music + timeline | All 7 steps built. Left: settle image stickiness |
| 3b Find Similar | Built: Delete by context, Find/Show Similar, Keep One, Keep as Group |
| Groups inside collections | Built 2026-09-24, Core through UI (`spec/plan.md`) |
| 4 Setlist export / import | Built, 4a–4d |
| E Video export | Built, E1–E5. Own spec `spec/video-export.md`. Left: a listen |
| 5 BGTools | Built, B1–B7. Own spec `spec/bgtools.md`. Left: Jason's hands-on pass; the Pan and Zoom cost; telling BGTools when a library moves |

Every schema upgrade is additive and tested by opening a library of the
version before (7 rows, 8 music, 9 markers, 10 editing state, 11 rhythm
patterns, 12 their note length, 13 groups). Before an upgrade the database is copied
to `Library.sqlite.v<N>.bak`. Video export needed no schema change: a video
slide's level line is slide settings, which are JSON.

`~/Applications/ShowTools.app` is **well behind HEAD** (built
2026-09-23, 05:30 — before Groups, PaneKit, the library panel, and every
menu this session added). `build/ShowTools.app` is current. BGTools'
desktop extension is running from the installed copy, so reinstalling
wasn't done without asking — say when to swap it in.

**The real library was set aside 2026-09-24** (Jason's own call, mid this
session): `~/Pictures/ShowTools Library.noindex` is now
`~/Pictures/ShowTools Library (2026-09-24).noindex`, untouched. The next
plain launch of the real app creates a fresh, empty library at the
default path.

## What's next

### Work queue for the Mac (from the cloud session, 2026-09-24)

Everything below is on **`main`** (merged from the cloud session's branch,
`claude/cloud-clauding-4lij0h`, 2026-09-24). **Pull `main` first.** The cloud session keeps to docs while the
Mac session works, so there are no clashes; pull again whenever it
pushes. Read `spec/history/2026-09-24-cloud-planning-aar.md` for what
happened and why. Load `showtools-testing` before any test copy (the
preferences-domain rules).

1. **Build and test the two unbuilt code changes** — done 2026-09-24.
   `swift test` (279 tests, 0 failures) and `./make-app.sh` both pass
   clean off `main`.
   - `7c1613a` (audit G1) and `dcf47c2` (audio names) both compile and
     the app launches fine against a scratch library. The hands-on
     checks (drop two files on Edit Slides / a sidebar show / Add to
     Show and read the Undo wording; the Audio row's title, icon, filter
     and context-menu text) still need doing — synthetic axtool clicks on
     the toolbar's "Add to Show" menu button and a tile-to-sidebar drag
     didn't reliably reproduce a real click/drop in this session (the
     popup never opened; the drop registered no undo step), so this
     stays on the "still needs Jason's hands" list rather than counting
     as verified.
2. ~~**⌘A in the Library grid: top priority**~~ — done 2026-09-24 (audit
   A1). Joins Delete/⌘Delete in the grid's `SingleKeys` monitor rather
   than a menu item (simpler, and the same fix the grid's focus problem
   already got); selects every tile in `visible`. Checked with a real
   ⌘A: 11/11 tiles, and the Search field's own select-all still works.
3. ~~**The rest of batch 1**~~ — done 2026-09-24: the Delete key and
   ⌘Delete in the Library pane (D1), undo for Delete Show (D2) and Rename
   Collection (D3). Found and fixed a real crash along the way — see
   Known issues below.
4. **Batch 2 — done 2026-09-24:**
   - ~~naming first, nothing made until OK (H1)~~ — New Collection done
     everywhere it's made; New Show deliberately left for the settings
     panel (`spec/simple-things-fast.md`), not a throwaway dialog now.
   - ~~Import can choose audio (H3), and the "song" error text (H4)~~ —
     done.
   - ~~empty-state buttons (H2, the plain tier)~~ — done: an empty
     collection gets Import…/Add from Library…, an empty show (Edit
     Slides) gets Add from Collection…/Import…, both through a new
     `MultiItemPicker` sheet.
   - ~~context menus, the obvious parts (C1–C3)~~ — done: Remove Image, Remove
     Transition and Remove Marker, each the exact `mutate` call its
     Delete-key handler already used. **Not confirmed by a real
     click** — the storyline's canvas didn't give axtool usable
     coordinates; wants Jason's own right-click. The fuller menus (C4–C7)
     wait for the right-click conversation, as planned.
   - **Update from the right-click conversation (2026-09-24):** the
     Library pane's and the Library grid's menus are now **settled**
     (`spec/conventions.md` §3, "Progress", stops 1 and 2), so those
     rows (C6, and the tile menu) needn't wait: build them in full.
     Items whose feature isn't built yet (Play without a show, Play on
     Desktop) go in greyed out, per Jason. The other menus still wait.
5. ~~**Groups inside collections**~~ — done 2026-09-24, Core through UI,
   including nesting and cross-collection dragging added after the fact
   on Jason's ask. 291 tests (was 279 before this item). Full story in
   `spec/plan.md`, "Groups inside collections". Real dragging (group
   onto group, onto its own collection, onto another) still wants
   Jason's hands — built and reasoned about, not clicked.
6. ~~**Batch 4: selection logic in Core, with tests**~~ — done 2026-09-24.
   `GridSelection` (`Sources/ShowToolsCore/GridSelection.swift`): pure
   functions over the caller's own `selected`/`anchor`/`base`/`cursor` —
   `click`, `commandClick`, `shiftClick` (fixes B3 and E1: a ⇧-click
   selects the range from the anchor, *replacing* the previous ⇧-range,
   not adding to it), and `step` (the arrow-key index arithmetic for
   B2/E2 — ± the column count for ↑/↓ in a grid, ±1 for a plain list;
   not wired into either view yet, since B2 waits for the grid's keyboard
   batch and E2 waits on Jason's ↑/↓-vs-←/→ decision). 14 new tests,
   including B3's and E1's exact worked examples from the audit. Wired
   into the Library grid's and the storyline's `click(_:)`, replacing
   each one's own buggy `.formUnion` logic (only ever added) and, in the
   storyline, an anchor that was wrongly derived from "the first selected
   slide" each time rather than kept as its own state.
   `swift test` (305, was 291) and `./make-app.sh` clean; smoke-launched
   again, no crash. *Check* (per the plan): the tests pass; a real
   ⇧-click in the grid and the storyline still wants Jason's hands.
7. ~~**Batch 5: Menus**~~ (A2, F1–F4, G5) — done 2026-09-24. Edit ▸
   Duplicate (⌘D) for slides in both modes (A2; not a lane image — no
   such action exists yet, left for the right-click conversation). The
   Show menu gained Play/Pause, Add Marker, Set Range In/Out (bare keys,
   named in the title), Clear Range (⌥X) and Loop Playback (⌘L, a real
   checkmarked `Toggle` now, not a hidden button) — all through one new
   `editShowCommands` focused value that's absent (so they disable
   themselves) outside Edit Show. The View menu gained Zoom In/Out
   (⌘=/⌘−, `storylineZoom` turned out to be one global `@AppStorage` key
   already, not per-window, so no focused value was needed), Zoom to Fit
   (⇧Z), Snapping, Show Inspector (⌥⌘I, moved off the toolbar button,
   which had the same shortcut twice) and Edit Slides/Edit Show (⌘1/⌘2,
   also plain `@AppStorage`). Get Info (⌘I) now answers for a show's
   slide selection too, not just the Library grid (F4). Show ▸ Play
   starts at the selected slide, matching the toolbar (G5) — free once
   A2/F4's selection focused value existed. Help ▸ Keyboard Shortcuts
   replaces SwiftUI's "help isn't available" default (F3), listing the
   bare-key commands that have nowhere else to show themselves.
   `swift test` (305) and `./make-app.sh` clean; smoke-launched, no
   crash. *Check* (per the plan): each item enabled at the right times,
   typing in Search still types, Show ▸ Play starts at the selection —
   all reasoned through, not clicked; wants Jason's hands, especially
   the new Keyboard Shortcuts window and the moved ⌥⌘I/⌘1/⌘2 shortcuts.
8. ~~**The PaneKit harness**~~ (`spec/panekit.md`, "The order", step 1):
   a standalone app with dummy content — done 2026-09-24 (see item 1
   under "The order from here" below).

9. **Jason's first-test work order** (`spec/history/2026-09-24-work-order.md`,
   folded into `spec/plan.md` "The range and the ruler", the Preview line,
   and `spec/bgtools.md` "Jason's first-test list"). One commit per item,
   least risky first. All ten are settled (2026-09-24); the one open
   detail, the ⌥ in item 4's modified double-click, is a proposal the
   build can use unless Jason says otherwise.
   1. **BGTools: All same → Synchronize.** User-facing words only; the
      stored key stays `allSame`. *Check:* the panel and the settings
      window say Synchronize, and a setting that was on before is still on
      after relaunch.
   2. **BGTools: a Quit you can find.** "Quit BGTools (stops desktop
      shows)" on the panel; ⌘Q with the settings window open. *Check:*
      both quit, and the desktop shows stop.
   3. ~~**The slide progress line fills left to right,** with a setting
      to hide it and Slide Progress on/off in the viewer's right-click.~~
      — done 2026-09-24 (`SlideProgress`, `EditShowView.swift`; the
      `showSlideProgress` key, shared by the Settings window's new
      Playback section and the slide-image context menu's toggle).
      *Check:* checked with axtool against a scratch library — the line
      now grows left to right through a slide (watched at 2.6s into a 4s
      clip, ~65% filled); the Settings toggle and the menu toggle both
      flip the same value; still dims when paused (unchanged code path).
      Not re-confirmed by ear/eye together over a whole show — that's
      folded into "A listen, twice over" below.
   4. **BGTools: the settings window opens on your screen**, with that
      screen's current Space selected. *Check:* with two monitors, open it
      from the panel on each; it lands there, selected.
   5. **BGTools: naming screens,** with the model-name tag. *Check:* name
      a monitor; the name shows in the window, the panel and the logs, with
      the tag; it survives unplugging and plugging back in.
   6. **The range: undoable, draggable ends, a lock.** *Check:* drag an
      end, ⌘Z puts it back; locked, a drag does nothing but I, O and ⌥X
      still work; undoing an ordinary edit still works as before.
   7. **The range button:** ⌥⌘-click (the view), ⇧⌥⌘-click (the whole
      show), the Show menu items and the button's right-click; locked
      beeps. *Check:* each sets the range as described; a locked range
      refuses with a beep.
   8. **Go Back / Go Forward (⌘[ / ⌘]) for the playhead,** with its scroll
      and zoom; the playhead stays out of ⌘Z. *Check:* click far along the
      ruler, ⌘[ returns the playhead and the view; each click-and-release
      and each key nudge is one step; ⌘Z still undoes only edits (and the
      range).
   9. **BGTools: the map view** beside the stack. *Check:* the monitors
      sit as on the desk, each with its Spaces; the choice between views
      is remembered.
   10. **Fill Range with Images…** *Check:* fill a 10-second range
       with 5 pictures, Even, both Replace and Displace, and compare with
       the rules in the plan; one ⌘Z undoes the whole fill; the dialog's
       feedback matches what's laid down.

   **Waiting on Jason (Claude's proposals):**
   - ~~P1~~ Settled: the hide setting applies to the whole app.
   - ~~P2~~ Settled: one lock, from either end's or the button's
     right-click; locked ends fade, no icon.
   - ~~P3~~ Settled: a plain click with no range makes one from the view.
   - ~~P4~~ Settled: Spaces can be named; they default to "<monitor
     name> Space 1", 2, and so on.
   - ~~P5~~ Settled: it always opens on the calling monitor, selected; a
     modified double-click (⌥, proposed) on a screen's box moves the window
     to that monitor.
   - ~~P6~~ Settled: the playhead stays out of ⌘Z and gets its own Go Back
     (⌘[) and Go Forward (⌘]); the range stays in ⌘Z.
   - ~~P7~~ Settled: a Map | List switch, remembered.
   - ~~P8~~ Settled: the fill always fits exactly, since it computes the
     lengths; nothing is greyed out; the dialog shows the count, each
     slide's length and the beats as feedback before OK.
   - ~~P9~~ Settled: the first slide is just shortened; there's no tail.

### The order from here (Jason, 2026-09-24)

Items 8 and 9 above, and settled work that never made the list, in one
order. Things that share code go together, so each area is opened once.
The work-order items keep their numbers (W1–W10 = item 9's 1–10).

1. ~~**PaneKit: compile, test, run the harness, first thing.**~~ — done
   2026-09-24: `swift build` and `swift test` (14 tests) both passed
   clean, no fixes needed against the cloud session's code. The
   harness's hands-on checks (dragging, edge handles, pop-out, relaunch
   persistence, undo, typing, Restore Defaults, the stress test) all
   passed, Jason's own hands. Step 1 closed; steps 2–4 in
   `spec/panekit.md` ("The order") wait their turn in the queue below.
2. ~~**BGTools quick wins:** Synchronize (W1), a findable Quit (W2).~~ —
   done 2026-09-24, `spec/bgtools.md` items 1–2. Left for Jason's hands:
   a real ⌘Q while the settings window is open, and the panel's Quit
   button.
3. ~~**The Library pane's and grid's menus**~~ (right-click stops 1–2,
   `spec/conventions.md` §3) — done 2026-09-24: Show in Finder is off the
   tile menu; a show's menu gained Duplicate Show (real: copies its
   slides, rows, music, markers and editor state) and an Export ▸
   submenu (Show…, Movie…, also replacing the File menu's two flat
   items) with Play on Desktop above it, greyed out (hands the show to
   BGTools; not built); the Library row, which had no menu at all, got
   one: Import…, New Collection…, Open Library Panel (greyed out; not
   built), Show in Finder. `xcodebuild` for the ShowTools scheme and
   `./make-app.sh debug` both build clean; `swift test` (305 tests)
   passes. **Left for Jason's hands:** every one of these menus — a
   synthetic right-click didn't open a context menu reliably in this
   session (a known limitation, see `showtools-testing`/AAR history), so
   only the File menu's Export submenu was confirmed by axtool, not the
   context menus themselves.
4. ~~**The viewer's menus + the progress line**~~ (stop 4 + W3) — done
   2026-09-24, except Select ▸ (`spec/conventions.md` §3, item 4): the
   slide-image menu (Open in Slide Editor, Show in Library, the
   quick-settings submenus, Reset Transform, Rotation Handles, Slide
   Progress), the pasteboard menu (Work Zoom, Onion Skin, Pop Out
   Viewer) and the frame strip's menu (Play from Here, Follow Storyline/
   Whole Show, Hide Frame Strip) are all built. Also built along the way:
   **Show in Library**, generally — `showInLibrary(_:model:undoManager:)`
   (`Libraries.swift`) opens the library panel and selects/scrolls to any
   file, reusable by every future menu that needs it (items 5–8 below).
   `swift test` (305) and `./make-app.sh` clean. **Checked with axtool
   against a scratch library, right-clicks worked reliably this time**
   (contra the Library-pane/grid session's note above) — every menu
   opened, every item fired: Rotation Handles toggled and reported back
   correctly on reopening, Show in Library opened the panel and selected
   the right file (confirmed by screenshot), Hide Frame Strip removed the
   strip and View ▸ Show Frame Strip brought it back, the progress line's
   new fill direction was watched mid-slide. **Left for Jason's hands:**
   all of it, still — axtool confirms the wiring, not the feel. **Known
   limitation, accepted on purpose** (not a bug to fix later without
   thought): the image vs. pasteboard menu is chosen from which image was
   last *clicked*, not from the right-click's own location, so
   right-clicking empty space right after selecting an image still shows
   the image's menu. Real click-location plumbing — and Select ▸, which
   needs the same thing — is its own later pass.
5. ~~**Edit Slides', the browser's and the inspector's menus**~~ (stops 3,
   5, 6) — done 2026-09-24, `spec/conventions.md` §3, items 3/5/6, except:
   Save as Preset… (no design for where presets live), the E/W/Q shortcut
   labels, the browser's own empty-space menu, the ⌥-swap for Copy/Paste
   Settings (built as four always-visible items instead), Replace
   Image… (deferred, `spec/plan.md` Later), a single control's own Reset
   to Default, and Length/Transition/Pan and Zoom/Rotation's section
   menus (they have no header to hang one on yet). New reusable pieces:
   `QuickSettingsMenu.swift` (Length/Transition/Pan and Zoom, shared with
   the viewer's own menu from item 4), `SlideClipboard.swift` (Copy/Paste
   and Copy/Paste Settings, pasteboard-backed), `SectionClipboard.swift`
   (per-section copy/paste, keyed by section name). `swift test` (305)
   and `./make-app.sh` clean; checked with axtool against a scratch
   library — the browser's use-only actions (Select in Timeline, Play
   from Here, Remove from Show, confirmed past its removal alert), Copy/
   Paste and Copy/Paste Settings in Edit Slides (slide count and settings
   actually changed, not just the menu opening), both inspector section
   menus, the header bar's Play from Here/Show in Library, and Use
   Defaults for All Slides (every slide's transition/length reverted to
   the show default) — all confirmed working, not just present.
6. **The range package — all of it done 2026-09-24:** W6 (undoable,
   draggable, lock) → W7 (the range button) → the ruler's and the range's
   right-click menu → W10 (Fill Range with Images…).
   - **W6:** the range's own points (`rangeIn`/`rangeOut`) are undoable
     now, unlike the rest of the editing state (`AppModel.update`'s undo
     restore keeps them from `before` instead of clobbering them with
     `now.editor` like everything else — a targeted exception, not a
     rule change). Dragging an end on the ruler (snaps like a trim,
     commits once on release), I, O and ⌥X all go through `mutate`
     instead of `engine.updateEditor`. A new `rangeLocked` field (schema
     unchanged — it's `ShowEditorState`, not a migration): one lock for
     the whole range, right-click of either end or the range button,
     locked ends fade (no icon, per Jason's call) and refuse a drag or a
     modifier-click, but still take I/O/⌥X since a key is a deliberate
     act. Checked with axtool against a scratch library: drag moves the
     right end and is undoable (confirmed via the saved show's `editor`
     JSON before/after ⌘Z), locked blocks the drag and the button's
     modifier-set-range commands while I/O still land, unlocking restores
     them. **Not checked:** the actual feel of a real drag (axtool's
     synthetic drag moved the end by more than its own translation
     implied — a tool artifact worth another look, not chased down this
     session) and the true ⌥⌘/⇧⌥⌘ chords (axtool's `click` only holds one
     modifier at a time, so only the button's plain-click and the Show
     menu's equivalents were exercised).
   - **W7:** the range button now acts like ⌥⌘-click when there's no
     range yet (Jason's settled call), otherwise shows/hides as before;
     ⌥⌘-click sets it to the view, ⇧⌥⌘-click to the whole show, both also
     on the Show menu (`Set Range to View`, `Set Range to Whole Show`,
     `hig-audit.md` F1) and the button's own right-click, alongside
     `Lock Range`. A locked range refuses either set-range command,
     checked through the Show menu (silent no-op there; the real button
     would beep — `NSSound.beep()`, unheard by axtool).
   - **The right-click menu:** right-clicking either end (already had
     Lock Range) or the shaded span itself now shows the same menu — Lock
     Range, Clear Range, and Fill Range with Images…, now built (below;
     the greyed-out stub is gone). Making the span
     hit-testable for its own right-click at first ate `scrubGesture` for
     its whole stretch — a real regression, caught by trying a left-click
     seek there after — so it carries its own copy of the same seek logic
     in the "storyline" named coordinate space instead of refusing hit
     testing; both the click-to-seek and the right-click menu were
     rechecked together afterward. Also folded in here: the music row's
     "double-click a song section sets the range" (`setRange` in
     `StorylineView`) was still going through `engine.updateEditor`, missed
     by W6 since it doesn't sit under the range button or the ruler's own
     ends — now `mutate`, undoable, and refuses a locked range like the
     button's modifier-clicks. Checked with axtool against a scratch
     library. **Not checked:** a real right-click (only screenshots
     confirm the menu opens with the right items).
   - **W10, Fill Range with Images…** (`FillRangeSheet.swift`,
     `RangeFill.swift` in Core): a Collection/Library toggle over a grid of
     thumbnails, picked in order (a numbered badge on each), a Transition
     picker (Show Default plus every style), a Rhythm picker — Even (the
     default) plus the apply sheet's own Beats/Bars/Seconds/Pattern modes,
     reusing `BeatPlan` and `BeatDetection.preview` to quantize onto
     detected beats under the range — and Replace/Displace. Nothing is
     greyed out (settled): a rhythm mode with no song under the range just
     behaves like Even, and the dialog shows the fill's own numbers
     instead — image count, each length, and how many of the needed
     interior cuts actually landed on a beat. `RangeFill.apply` (Core,
     unit-tested, 13 tests) does the trims and inserts described in the
     plan, plus one gap the plan didn't spell out and one found by hand:
     a range wholly inside one slide needs a second use of that file for
     what continues past the range's end, to keep Replace's "show length
     doesn't change" rule (not a split of the fill's own slides — the
     ordinary way a file appears twice); and a trim that rounds to nothing
     (the range starts or ends exactly on an existing slide's own edge)
     drops that slide outright instead of leaving a sub-50ms stub behind —
     caught by hand against a scratch library on the very first try, fixed,
     and pinned down with two more tests. Picking from the Library adds
     those pictures to the show's collection first (`bringIntoCollection`,
     the same confirmation as any other add), as its own step before the
     fill's undo entry. Checked end to end with axtool against a scratch
     library: opened the dialog, picked pictures from the Collection tab,
     watched the feedback update live, filled, and confirmed with
     `sqlite3` that the slides table matched what the dialog promised, the
     fix for the stub included, and that ⌘Z removes it in one step.
     **Not checked:** the Library tab, a song under the range (so a
     non-Even rhythm has something real to quantize onto), Displace, and a
     real click — only axtool's.
7. **Timeline keys — done 2026-09-24:** the arrow keys (E2; `spec/conventions.md`
   §2: ← → through a row's items, ↑ ↓ between rows, ← → in the ruler nudge
   the playhead) and Go Back / Go Forward (W8).
   - **Arrow keys:** batch 4's `GridSelection.step` finally wired in.
     Which row is "current" comes from whichever selection is
     active — slides, the transition it leads into, a lane image or a
     song — since `EditShowView` already keeps those mutually exclusive;
     nothing selected falls back to nudging the playhead (one frame,
     1/30 s), as the settled decision says "in the ruler" should. ↑ ↓
     switch to the row above/below in the show's own row order and land
     on whichever item there sits nearest the old selection's time (or
     the playhead, from nothing). ⇧← / ⇧→ extend the slides row's
     selection exactly as a ⇧-click would (its anchor/base/cursor moved
     from `StorylineView`'s own `@State` into `ShowSession` — a click and
     an arrow key both touch it now, so they can't desync); the other
     rows are single-selection in this UI, so ⇧ has no effect there.
     **A gap found by hand, not fixed:** moving to an empty row (this
     show has no lane images or songs) deselects everything instead of
     skipping to the next non-empty row — reasoned as acceptable for now,
     worth Jason's opinion.
   - **Go Back / Go Forward (W8):** a browser-style two-stack history on
     `ShowSession` (`PlayheadStep`: time, zoom, and the slide nearest the
     ruler's left edge in place of a raw scroll offset, which
     `ScrollViewReader` has no way to restore directly — it only scrolls
     to a view's id, so restoring re-centres on that slide instead). A
     ruler click or scrub drag pushes one step at its start, not on every
     `onChanged` tick; a keyboard nudge pushes one per press; Go Back and
     Go Forward themselves push the opposite direction's stack, browser-
     style, and never register as edits. ⌘[ / ⌘] and matching View menu
     items (`Go Back`, `Go Forward`, disabled at either end of the
     history). Checked with axtool against a scratch library: a slide
     selection, ↑ to its transition, ↑ again to the (empty) images row,
     → moving the selection, a ruler click, Go Back and Go Forward both
     landing on the exact recorded times, and `Edit ▸ Undo` staying
     disabled throughout (confirming the playhead really does stay out of
     ⌘Z). **Not checked:** whether Go Back's scroll restoration (jumping
     to the nearest slide rather than the exact pixel offset) actually
     looks right zoomed out with a lot of storyline in view — only the
     time and zoom were confirmed, not a real look at the scroll.
8. **Drops onto slides + Replace Image…:** ~~Replace Image…~~ — done
   2026-09-24 — → the slide list inserts where a drop lands (G2), and a
   drop onto a slide offers Replace or Insert, still to come.
   - **Replace Image…** (plan.md, "Replace a slide's image"): only a
     slide's (or lane image's) `itemID` changes — length, transition, Pan
     and Zoom, transform and effects all carry over unchanged, since
     every position in its settings is already a fraction of the image,
     not pixels. One tap in a new `ReplaceImagePicker` (the same shape as
     `LibraryPicker`, scoped to the show's own collection, the current
     image shown disabled) picks and closes; one undo step
     (`SlideActions.replaceImage`). Wired into all four places the plan
     names: a slide's menu in both Edit Slides' list and the storyline,
     a lane image's menu, and the inspector's header bar (the "deferred"
     note there is gone). Checked with axtool against a scratch library:
     opened from the storyline, swapped photo_01.jpg for photo_06.jpg,
     confirmed the slide's `item_id` changed in the saved show and
     `⌘Z` put it back in one step. **Not checked:** the Edit Slides list,
     the lane image and the inspector menus, or a real click anywhere —
     only the storyline's was actually exercised.
9. **The grid's keyboard** (audit batch 7: B1, B2, B5, B6): arrow keys,
   Quick Look on ⌘Y, Return renames, double-click.
10. **BGTools batch:** names (W5) → the map view (W9) → the window opening
    on your screen, with ⌥-double-click (W4).

Then: the design conversation step 4 itself needed — the library panel, an
actual detached pane, the Slide Editor (`spec/windows.md`) — now that
everything ahead of it is done, moved up this list on purpose to de-risk
it early, 2026-09-24: steps 2 and 3 (the app's main window and Edit
Show's/Edit Slides' columns), the show session (its own prerequisite),
and `nearIsRigid` (found watching Jason use it — Edit Show's list column
now only resizes from its own divider; `spec/panekit.md`, "Building a
row"). **Step 4 itself: the order is settled** (Slide Editor, library
panel, one detachable area, timeline pane last), **and both the Slide
Editor and the library panel are built**, 2026-09-24: the Slide Editor
(v1: the image, its handles and the full inspector, opened by
double-click on a slide, settled over the inspector, in Edit Slides'
list or the storyline, or "Open in Slide Editor" on either's context
menu — `spec/panekit.md`, "Step 4, first piece"); the library panel (a
floating window on the whole library grid, opened from "Open Library
Panel" on the Library item's context menu, previously stubbed in greyed
out — `spec/panekit.md`, "Step 4, second piece"). Left of step 4: the
one detachable area. And the New Show panel
(`spec/simple-things-fast.md`).

### Also next

1. **A listen, twice over.** (1) An exported movie against the same show
   playing: timing, crossfades, a video slide's sound against a song.
   (2) A video slide's sound in the app (V6): a clip with its middle
   dropped, a video against a song (they should just mix, no ducking),
   and whether the level glides or steps audibly — live it is set once
   per drawn frame, in an export per sample, so the export may be the
   smoother of the two.
2. **A show made from Jason's own photos and music**, imported by hand.
   This is what v1 end-to-end still needs. The demo show was seeded by a
   script, so ingest-by-drag, building a show by hand and editing it are
   untested by a person.
3. **Telling BGTools when a library moves** (B7 left it open).
4. **Expected Mac behaviour** — `spec/hig-audit.md` (audited from code
   2026-09-24; G1 fixed, unbuilt; the rest is the work queue above). Missing conventions: ⌘A, ⌘D, arrow keys
   and Quick Look in the grid; context menus on lane images, transitions
   and markers; Edit Show's commands in no menu; Edit Slides and Edit
   Show disagreeing. One real bug: **adding slides by a drop onto Edit
   Slides, a show in the Library pane or Add to Show can't be undone** (G1). Eight fix
   batches, least risky first; three decisions for Jason.

**Ken Burns → "Pan and Zoom" — done 2026-09-23** (`8db7ffc`, `a0be113`),
in the UI, the code, the slide-settings JSON keys (`panAndZoom`,
`panAndZoomSeed`) and the setlist TSV columns (`panzoom_*`). No old
spelling was kept readable. The show-level default was already `.off`;
BGTools' random-mode default was the one place still `.auto`, now `.off`
too. `~/Applications/ShowTools.app` is rebuilt and reinstalled from HEAD.
**A setlist folder or `show.json` exported before this date will lose its
Pan and Zoom setting, silently, on re-import** — confirmed by hand
against a real export. Full story: `spec/history/2026-09-23-pan-and-zoom-rename.md`.

**Pan and Zoom only zooms** (Jason, 2026-09-24): Auto is mostly a zoom,
and Custom's pan is two small frames to drag in the inspector. Wanted: a
direction, and aiming the zoom by clicking the image. In the plan, under
Later.

Parked: image stickiness, a guided first run (`spec/first-run-brief.md`),
and Flush presets from 2a.

**Next conversation: right-click menus,** area by area, with
`spec/anatomy.md` as the guide. The plan is at the end of
`spec/conventions.md`. Finish the other universals first.

## Still needs Jason's hands

- **Timeline keys** (built 2026-09-24, `spec/conventions.md` §2): arrow-key
  navigation across all four rows and Go Back/Forward — checked with
  axtool against a scratch library's saved state (times, the enabled/
  disabled menu items, `Edit ▸ Undo` staying off), never by a real
  keypress or a real look at the storyline. Worth a particular look: the
  empty-row deselect gap noted above, and whether Go Back's scroll
  restoration (the nearest slide, not the exact offset) feels right.
- **The whole range package, W6–W10** (built 2026-09-24, `spec/plan.md`
  "The range and the ruler" and "Fill the range with images"): dragging
  an end, the lock (right-click of either end, the shaded span or the
  button), I/O/⌥X still landing while locked, the range button's
  plain-click/⌥⌘-click/⇧⌥⌘-click/right-click, the shaded span's own
  right-click menu, double-clicking a song section to set the range, and
  the Fill Range with Images dialog itself — all reasoned through and
  checked with axtool against a saved show's `editor` and `slides` tables
  and screenshots, never by a real drag or a real modifier-click (axtool's
  `click` can't hold two modifiers at once, so ⌥⌘ and ⇧⌥⌘ themselves are
  unverified beyond their Show-menu equivalents). Worth a particular look:
  whether a real drag feels right — the synthetic one moved further than
  its own on-screen distance implied, which may just be a tool artifact;
  whether scrubbing still feels normal across the whole ruler now that the
  range's shaded span carries its own copy of the seek gesture alongside
  `RulerView`'s; the Fill dialog's Library tab and a Displace fill (only
  Collection and Replace were clicked through); and the one-slide-inside-
  the-range edge case in `RangeFill` (a second use of the same file for
  what continues past the range's end) — reasoned through and tested, but
  not something the plan itself spelled out, so worth Jason's own read.
- **The viewer's menus, Show in Library, and the progress line fix**
  (built 2026-09-24, `spec/conventions.md` §3, item 4): every menu opens
  with the right items and every action was confirmed by its actual
  effect with axtool (Rotation Handles and Slide Progress toggle and
  report back, Show in Library opens the panel and selects the right
  file, Hide/Show Frame Strip round-trips, the progress line fills left
  to right), but none of it has been used by a real click yet. Worth a
  particular look: the known, accepted limitation that the image vs.
  pasteboard menu goes by which image was last clicked, not by the
  right-click's own location.
- **Edit Slides', the browser's and the inspector's menus** (built
  2026-09-24, `spec/conventions.md` §3, items 3/5/6): Copy/Paste and
  Copy/Paste Settings, the quick-settings submenus, Use Defaults for All
  Slides, the browser's Select in Timeline/Play from Here/Remove from
  Show, and both inspector section menus — all confirmed by their actual
  effect with axtool (slide counts and settings genuinely changed, not
  just the menu opening), never by a real click. Worth a particular
  look: Copy/Paste Settings are meant to swap in over Copy/Paste only
  while ⌥ is held, but are built as four always-visible items instead
  (SwiftUI's `.contextMenu` can't declare AppKit's alternate items) — if
  that reads as clutter in practice, the ⌥-swap is its own follow-up.
- **The library panel** (built 2026-09-24, `spec/panekit.md`, "Step 4,
  second piece"): opens and shows the whole library correctly, checked
  with axtool against a scratch library, but a real drag from it (its own
  reason for existing — filling a new collection with the panel floating
  over it) hasn't been tried by hand.
- **The grid's list view at the size slider's minimum, and the panel's
  slider now independent of the main window's** (Jason, 2026-09-24,
  `spec/windows.md` answer 6): checked with axtool — dragging the slider
  to its floor and back switches cleanly between a single-column list
  (small icon, filename, full-width selection highlight) and the tile
  grid, selection carries across the switch; the library panel's slider
  and the main window's grid now keep their own sizes (`gridTileSize` vs
  `gridTileSize.panel`), checked with both windows open at once, one in
  list view and the other mid-size — but never watched by a real drag of
  the actual slider control.
- **Audit G1 and the audio-naming pass** (`7c1613a`, `dcf47c2`): both
  build and the app launches, but the hands-on checks weren't done this
  session — see the work queue above.
- **Context menus C1–C3** (Remove Image/Transition/Marker): build and
  test clean, but not confirmed by a real click — the storyline canvas
  resisted synthetic clicking this session.
- **Groups in the Library pane** (built 2026-09-24): drag-to-add from the
  grid and from Finder, nested folding, New Group naming, the delete
  notice's wording, the browser's group filter, and Keep as Group. Also
  new: **dragging a group onto another to nest it, onto its own
  collection to un-nest it, and onto a different collection**, with the
  "images will be added" notice and its suppression checkbox. All of it
  only smoke-tested (launch, no crash), not clicked by a person.
- **⇧-click in the Library grid and the storyline** (batch 4, built
  2026-09-24): `GridSelection`'s logic is unit-tested against the audit's
  own worked examples, but a real ⇧-click, ⇧-click, ⇧-click hasn't been
  tried by hand in either place.
- **The menus batch 5 built 2026-09-24**: the Show and View menu items,
  Get Info from a slide selection, Show ▸ Play starting at the
  selection, and Help ▸ Keyboard Shortcuts — all reasoned through and
  compiled clean, but a menu can only really be checked by opening it.
  Worth a particular look: the toolbar's Inspector button and ⌘1/⌘2 lost
  or gained their shortcuts moving to the View menu, so it's worth
  confirming nothing doubled up or went silent.
- **The Rhythm tool** (step 7): the panel's look (the space around the
  form, the notation's size: a staff space is 5.5 pt), Listen by ear on
  real music, Space stopping Listen, and whether 145 BPM is right for
  Fly Me to the Moon (or double).
- **Listening:** music sync, fades, crossfades; Bluetooth headphones'
  delay (the output latency is subtracted, but it's untested).
- **Inspector sliders' live preview** — built (`b66b4af`) but never
  watched by eye; the commit says so.
- **Dragging a song in from Finder or Music.**
- **Look and feel:** the row handles (10 pt wide), the drawers, the level
  line's handles, whether a line on every clip is too busy in the thin
  images row, and the transport's new toggles.
- **BGTools:** unlocking a private library with Touch ID, the panel
  closing on a click elsewhere, Space-switch pausing — not yet re-done
  against the nested BGTools.
- **From before Phase 3:** cross-app drags from Finder and Photos, Touch
  ID and the Mac's password, pinch, a second screen, cursors, and one
  real ⌘Z with the Info panel focused.

## Open questions

- **Image stickiness (2c)**, at the end of Phase 3: should a lane image
  stay at its time on the clock, or move with the slide it starts over
  when slides are trimmed or reordered? For now it stays on the clock.
- **Windows of their own** (`spec/windows.md`): which areas detach, the
  Slide Editor, the library panel and Show in Library. Jason answered six
  of seven questions 2026-09-24; what comes first is still open. Its prerequisite is moving a show's
  editing state out of the views, which the audit's menu work wants too.
- **Simple things fast** (`spec/simple-things-fast.md`; was "a simple
  way in"). The editor does a lot, but simple things aren't fast. There
  are three answers: the guided first run, playing a library or
  collection without building a show, and three levels (Basic, Advanced,
  "Bring it on!"). Four questions for Jason.

## Known issues

- **The layout-loop crash — fixed 2026-09-23.** `NSGenericException` from
  AppKit's layout-loop guard, on selecting a show or switching Edit Slides
  ↔ Edit Show. **Confirmed cause:** SwiftUI's `.inspector()` modifier on
  `ShowView`'s `.slides` case (`spec/history/2026-09-23-crash-hunt-session3.md`).
  **The fix, landed:** `spec/edit-slides-inspector-port.md` — Edit Slides'
  inspector is now ported onto the same hand-rolled `ColumnsSplitView`
  mechanism `EditShowView` already used (a new two-pane shape, main +
  inspector, no middle list column). Verified against a clean rebuild and
  the exact repro that crashed every prior build: a copy of the real
  library, "Trucks to the Future" selected, 32 rapid Edit Slides ↔ Edit
  Show toggles at ~0.4s pacing — zero new entries in
  `~/Library/Logs/ShowTools-exception.log` (6060 before and after), and
  the ported inspector opens/closes from the toolbar and by double-click
  and shows the right slide's settings. Full story:
  `spec/history/2026-09-23-crash-hunt.md`,
  `spec/history/2026-09-23-crash-hunt-session2.md`,
  `spec/history/2026-09-23-crash-hunt-session3.md` (the one with the
  actual cause).
  **The same guard fired again, in a new place, 2026-09-24:** a
  `SingleKeys` key monitor (audit D1) in `.background()` directly on the
  sidebar `List` — a real `NSTableView`, unlike the grid's plain
  `ScrollView` where the same technique is fine — crashed on undoing a
  show deletion (`ShowTools-2026-09-24-034845.ips`). Fixed by moving the
  monitor to `.background()` on the whole `NavigationSplitView` instead of
  the List; the exact repro (select a show, ⌘Delete, ⌘Z) no longer
  crashes. **Lesson: `.background(SingleKeys)` is safe on a plain
  SwiftUI container, not on a `List` or anything else AppKit backs with
  its own constraint-based layout** — worth checking before adding one to
  Edit Slides' or the storyline's own Lists for later audit items.
- **Pulling the inspector's divider far to the left breaks the layout**
  ("smashes both sides out off the screen"). Seen once in a test copy
  dragging from the right edge to x=300. `revealByDragging` is the obvious
  suspect — it clamps the width it sets, but nothing re-checks the columns
  as a whole. Needs reproducing before anything is changed.
- **⌥⌘0 (Restore Default Layout) raised the layout-loop exception once**,
  and killed the app, on 2026-09-23: *before* the cause was confirmed as
  SwiftUI's `.inspector()` and fixed. Not seen since the fix; probably that
  same crash. The Library pane was a suspect only by coincidence (Jason). Its
  known bugs are display bugs. `DefaultLayout` still skips the Library pane on
  that stale reasoning, which is worth retrying.
- **A song lying wholly inside another** plays over it without crossfading
  (only a partial overlap crossfades). Level tops out at 100%.
- **The last slide cuts to the background** when something runs past the
  slides; a fade could come later.
- **The row drawers hold no controls yet.** Scrub audio isn't built;
  scrubbing is silent.
- **CPU** is about 33–37% while the editor plays; memory about 430 MB.
  BGTools' desktop mode is ~2% since B6, except while Pan and Zoom moves,
  which costs about 40% of a core because it really does redraw every
  frame — worth a look. It's why BGTools' random-mode default was flipped
  to `.off` 2026-09-23 (it's opt-in now, not a cost every random desktop
  show pays).
- **Video:** it can't go in the lane yet. The frame strip shows a video's
  first frame, the onion skin skips video slides, and `stcli render` draws
  a video slide as the background colour — only `stcli movie` and the app
  go through `MovieMedia`. A video slide's sound is decoded whole into
  memory when exporting; fine for slides, worth revisiting if whole films
  ever become slides.
- The zoomed-out work area doesn't draw a lane image's overhang past the
  frame.
- Accordion was dropped, and Page Curl is offered as "Page Turn".

## Test things installed on Jason's Mac

`ShowTools.app` in `~/Applications` (the real one, with BGTools and the
tiles inside), `build/DesktopProbe.app` (not running), and XcodeGen
(`brew install xcodegen`, now required to build the app at all). Stale
Background Task Management entries for `com.jhg.bgtools` and two
`com.jhg.nestprobe` ids remain — `sfltool resetbtm` would clear them but
resets every app's login items, so they are left alone.

## Quick start

```sh
swift test                                  # 306 core + 12 BGTools tests
./make-app.sh                               # → build/ShowTools.app
tools/make-test-library.sh <scratch>/STTest # scratch library + generated media
open -n --env SHOWTOOLS_LIBRARY=<scratch>/STTest/TestLib.noindex build/ShowTools.app
```

Before launching any test copy, read the `showtools-testing` skill: a test
copy shares Jason's preferences domain, and a crashed one shuts his real
app out.
