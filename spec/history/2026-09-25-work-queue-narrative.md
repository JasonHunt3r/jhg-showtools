# 2026-09-24/25 — the cloud-planning work queue, done

Moved out of `spec/status.md` 2026-09-25 (docs hygiene pass): this is the
full dated narrative for the work queue that came out of the 2026-09-24
cloud planning session (`spec/history/2026-09-24-cloud-planning-aar.md`)
and the order Jason picked to build it in. Every item below is done —
`spec/status.md`'s "Where it stands" table has the present-tense summary.
Kept here for the *why* and the *how*, not for current state.


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
8. **Drops onto slides + Replace Image… — done 2026-09-24.**
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
   - **Drops onto slides — G2's fix, and Replace-or-Insert** (plan.md,
     "dragging a file onto a slide... the drop offers Replace or Insert,
     as Final Cut's replace edit does"): geometry, not a dialog — the
     middle 60% of a slide's block is the replace zone (one picture only;
     several always insert), its outer edges still insert there, matching
     the feel of Final Cut's own affordance and what a tight zoom already
     made true of the old code. The storyline's `dropTarget` now returns
     `.replace` or `.insert`, with matching visual feedback (a highlighted
     box around the whole slide, or the existing thin insertion line).
     **G2 itself, in the Edit Slides list** (audit, Med — dropping between
     slides 3 and 4 used to append to the end regardless): each `SlideRow`
     now has its own `.onDrop`, fixed pixel bands (top 12pt / middle /
     bottom 12pt, not measured with a `GeometryReader` — one inside a
     `List` row measures during layout, a standing crash risk in this app,
     CLAUDE.md) — the list-level `.onDrop` that used to always append is
     now only the fallback for a drop in empty space below the last row.
     Songs dropped on either still have no effect (G2's "could be
     refused" — left as a silent no-op, not an explicit refusal). Checked
     with axtool: **a real internal drag** (Library sidebar to a storyline
     slide) confirmed both directions — dropped on the middle, it replaced
     the slide's image; dropped near an edge, it inserted a new slide
     there instead — each its own undo step. **Not checked:** the Edit
     Slides list's own drop (its browser panel and the Library window
     overlap in this scratch setup, and a cross-window synthetic drag has
     a documented history of not reproducing reliably in this app — same
     limitation noted in earlier sessions); real visual feedback by eye.
9. ~~**The grid's keyboard**~~ (audit batch 7: B1, B2, B5, B6) — done
   2026-09-25. `GridSelection.step` (already built and tested, batch 4)
   wired into the Library grid's own `SingleKeys` handler alongside
   Delete/⌘Delete/⌘A: ← → step one tile, ↑ ↓ step a whole row (a new
   `columnCount`, worked out from the grid's own measured width the same
   way `.adaptive(minimum:maximum:)` does, since SwiftUI doesn't expose
   the column count itself), ⇧ extends from the anchor exactly as
   ⇧-click does, and the cursor scrolls into view (`ScrollViewProxy`,
   already in scope for `scrollingGrid`). Return renames the selection
   (reuses `renameIDs`, the same sheet the context menu's Rename… opens).
   Quick Look (B5, B6, settled as double-click's meaning in
   `spec/conventions.md`) is new: `QuickLookController.swift`, a direct
   `QLPreviewPanel.shared()` data source (not the full
   `acceptsPreviewPanelControl` responder-chain dance — this app never
   puts Quick Look behind Space, which is play/pause everywhere, so
   there's no other owner to hand the panel to). **⌘Y is a real menu
   shortcut** (`requestLibraryQuickLook`, alongside Get Info and
   Rename…), not `SingleKeys`: a first attempt used `SingleKeys` and
   ⌘Y stopped closing the panel once the panel itself — a different
   `NSWindow` — was key, since a window-scoped local monitor never sees
   that window's events; a real `NSMenuItem` shortcut fires wherever the
   app's focus is, which fixed it. Double-click on a tile opens Quick
   Look too (`.onTapGesture(count: 2)`, before the plain one so SwiftUI
   doesn't fire both). `swift build`, `swift test` (306) and
   `./make-app.sh` all clean. **Checked with axtool against a scratch
   library:** click selects, → and ↓ land on the right tile (↓ moved
   exactly one row down, confirming `columnCount`'s math against the
   real `.adaptive` layout), ⇧← extends to 2 selected, Return opens
   "Rename 2 Items", ⌘Y opens Quick Look on the first of a 2-item
   selection (confirmed by screenshot — the right file, "photo_05.jpg"),
   double-click opens it too, and ⌘Y a second time closes it **even
   while the Quick Look panel itself was the key window** — the exact
   case the menu-shortcut fix was for. Prefs diffed clean against a
   pre-session export; no stray `runningTestLaunches` after quitting.
   **Not checked:** a real keypress or double-click by hand — every
   check above was axtool's.
10. ~~**BGTools batch:**~~ names (W5), the map view (W9), and the window
    opening on your screen with ⌥-double-click (W4) — all done 2026-09-25.
    Full story in `spec/bgtools.md`, items 3–5. Checked with axtool
    against a scratch `BGTOOLS_SETTINGS` file: renamed the one monitor
    here and a Space, both showing live with no relaunch and persisted to
    `settings.json`; the Map | List switch works, the bottom section
    (Synchronize/New screens/Random pictures) stays reachable in both; the
    window opened positioned and Space-selected correctly, on this Mac's
    one monitor. **Not checked:** more than one physical monitor, and
    every real click (menus and text entry only).

Then: the design conversation step 4 itself needed — the library panel, an
actual detached pane, the Slide Editor (`spec/windows.md`) — now that
everything ahead of it is done, moved up this list on purpose to de-risk
it early, 2026-09-24: steps 2 and 3 (the app's main window and Edit
Show's/Edit Slides' columns), the show session (its own prerequisite),
and `nearIsRigid` (found watching Jason use it — Edit Show's list column
now only resizes from its own divider; `spec/panekit.md`, "Building a
row"). **Step 4 itself: the order is settled** (Slide Editor, library
panel, one detachable area, timeline pane last), **and the Slide Editor,
the library panel, and one detachable area are all built**: the Slide
Editor (v1: the image, its handles and the full inspector, opened by
double-click on a slide, settled over the inspector, in Edit Slides'
list or the storyline, or "Open in Slide Editor" on either's context
menu — `spec/panekit.md`, "Step 4, first piece", 2026-09-24); the library
panel (a floating window on the whole library grid, opened from "Open
Library Panel" on the Library item's context menu, previously stubbed in
greyed out — `spec/panekit.md`, "Step 4, second piece", 2026-09-24); Edit
Show's inspector popping out into its own window (View ▸ "Inspector in
Its Own Window"), the first detachable area, **built 2026-09-25**
(`spec/panekit.md`, "The order," step 4; "Pane ⇄ panel"). It proves the
main window closing up and cross-window state sharing (checked with
axtool against a scratch library: pops out beside the main window, the
list column grows into the vacated space, selecting a slide in the main
window live-updates the popped-out inspector, and an edit made there
saves correctly). **Undo was a real, measured gap, fixed the same
session:** `Edit ▸ Undo`/⌘Z didn't reach the shared history from the
popped-out window, only from the main one, despite `PanePanel`'s
`undoManager` override returning the identical `UndoManager` object
(checked by `ObjectIdentifier`) — the cause was SwiftUI's own automatic
Undo/Redo commands being scoped to its `Scene` graph, which a PaneKit
pop-out sits outside of, so they never asked the override at all.
`ShowToolsApp.swift`'s new `UndoMenuState` replaces those commands with
ones that ask `NSApp.keyWindow?.undoManager` directly, app-wide — checked
with axtool against a scratch library: `Edit ▸ Undo` reads "Undo Move"
(the real action name) and a real ⌘Z from the popped-out window reverts
the edit (confirmed against the saved show's JSON), ⇧⌘Z redoes it.
`swift test` (306) and `./make-app.sh` clean. **The timeline pane, step
4's last piece, built the same session** (View ▸ "Timeline in Its Own
Window"; `spec/panekit.md`, "The order," step 5): pops out as an ordinary
window (it can go behind, unlike the Inspector's floating panel); the
columns above grow to fill the vacated height when it does. This was the
real keys test step 4 flagged — bare-key shortcuts (Space, J/K/L, M, I,
O, N, arrows) needed `shortcuts(engine)` moved onto the storyline pane's
own content so `SingleKeys` re-attaches its key monitor to whichever
window the pane is actually in; confirmed with a real Space keypress
toggling playback from the popped-out window. Undo/Redo, already fixed
app-wide, needed no further work — confirmed with a real Set Range In
from the popped-out Timeline window and a real ⌘Z undoing it.
**`editShowCommands` — found broken, fixed the same session:** the
Show/View menu's items (Play/Pause, Add Marker, Set Range, Zoom, Go
Back/Forward, Loop) read disabled while the Timeline window was key —
same cause as the Undo gap, `.focusedSceneValue` being Scene-scoped.
Moved `EditShowCommandsValue` off `@FocusedValue`/`.focusedSceneValue`
onto a plain stored property, `AppModel.editShowCommands` (`EditShowView`
sets it via `.onChange`, reading the saved `show` rather than
`engine.show` to dodge `PlaybackEngine.show`'s own `@ObservationIgnored`
trap, showtools-gotchas). Checked with axtool against a scratch library,
all from the popped-out Timeline window: Loop Playback toggled through
the menu and the saved show's JSON flipped, Set Range In through the
menu wrote `editor.rangeIn`, and Go Back went from disabled to enabled
after a real arrow-key nudge. `swift test` (306) and `./make-app.sh`
clean.

**The timeline pane only spanned the detail column, not the window —
fixed later the same day (2026-09-25).** Jason's own words: "the
timeline is supposed to go the whole width under the library column."
The pane moved off `model.editShowColumns` (nested inside Edit Show's
own three columns) onto `AppModel.mainPanes`'s own tree — a new outer
split wrapping the library|detail split — rendered by `MainView`
(`EditShowTimelinePane.swift`, pulled out of `EditShowView`) rather than
by `EditShowView` itself, since handing a built view from one view's
`body` to another for the same update pass risks the same trap SwiftUI's
"don't mutate state during a view update" rule exists for. Auto-closes
(`model.mainPanes.setOpen("window", …)`) outside Edit Show, rather than
showing empty space. Two more bugs found moving it: a Delete-key race
between two separate `SingleKeys` instances on the same window (a slide
selected in the storyline, Delete pressed, sometimes deleted the whole
show instead — settled with one handler, `SlideActions.removeSelected`,
tried first by `MainView`'s existing sidebar Delete handler), and a
popped-out Timeline window left open and blank after leaving Edit Show
(settled by putting it back first). `spec/panekit.md`, "The order," step
5, has the full story. Checked with axtool against a scratch library:
the timeline sits at x=0 under the Library pane, library and detail grow
to fill the window's full height when it's closed, Edit Slides closes it
and Edit Show restores it docked and full width, the pop-out and its
Undo/Redo and menu commands still work, and a real slide Delete removes
just that slide (the removal notice, not "Delete Show?") with ⌘Z putting
it back. `swift test` (306) and `./make-app.sh` clean. And the New Show
panel (`spec/simple-things-fast.md`).
