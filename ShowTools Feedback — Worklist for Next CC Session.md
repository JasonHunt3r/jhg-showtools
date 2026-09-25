# ShowTools Feedback — Worklist for Next CC Session

Sep 25, 2026 · @Jason Hunter

## How to read this

Items are grouped by subsystem (chrome, panels, library, etc.) rather than the order they were written in, since several touch the same underlying code. Each carries a priority tag:

- **P0** — bug/broken interaction, blocks normal use
- **P1** — core UX gap, works but wrong or incomplete
- **P2** — polish, cosmetic, or nice-to-have
- **P3** — needs a design decision or more spec before CC can build it

The final section rolls everything into one build-order list for the next session.

## Window chrome & visual style

- **P2 — Kill the rounded control containers in the header bar.** Look for a tighter, "Pro" style API/system look: smaller type, tighter spacing, no oversized buttons/sliders.
- **P3 — Glass/vibrancy material.** Windows currently read as opaque under dark mode; unclear whether the intended glass/translucency effect is actually being applied. Needs a check in light mode too, since that hasn't been tried yet.
- **P2 — App-wide corner-radius override.** Ability to override the window corner radius and other rounded-corner elements globally.
- **P0 — Settings panel runs off the bottom of the screen** in a narrow stack. Settings windows need to stay contained within the available screen space.

## Panel layout & drawer behavior

- **P0 — Collections column width doesn't behave correctly on inspector close.** Closing the inspector drawer currently hands its freed width to the collections column. Instead, the collections column should stay a fixed width and slide, anchored to the divider — the freed width should go to the main window.
- **P1 — Collections should get its own closed-drawer state**, stacking up against the closed inspector on the right side, matching the inspector's collapse behavior.&#32;
- **P0 — Inspector panel z-order bug.** The inspector panel currently floats on top of other app windows (e.g. over a text editor). It should stay within its own app's window layer, underneath any preferences/settings layer. Worth writing up an explicit window-layer hierarchy so this class of bug doesn't recur, and auditing the other pop-out windows added in the latest round of work against it.&#32;
- **P1 — Inspector header should sit at the top of the column when empty.**
- **P2 — Frames row collapse.** Let the frames row handle collapse down to a stacked, collapsed handle (mirrors the drawer-stacking idea above).

## Library & collections management

- **P0 — Clicking the library pane background ****s****h****o****u****l****d**** ****n****o****t**** ****c****h****a****ng****e**** ****t****o gri****d v****iew. ****I****t**** ****s****h****o****uld****n****'****t**** ****d****o**** ****a****nythi****ng.**
- **P0 — No right-click response anywhere in the main window's b****a****c****k****g****r****o****u****n****d**** area****s****.**
- **P1 — Collections list minimum width is too wide.** Needs a smaller floor.
- **P2 — Add "Change Library" to the library header's right-click menu.**
- **P1 — Add an option to delete from the library when deleting a collection or group.**** ****I****n**** ****t****h****e**** ****d****ia****log**** ****a****s**** ****a**** ****c****h****e****c****k**** ****b****o****x**** ****s****h****o****u****l****d**** ****w****or****k.**
- **P1 — Reordering in collections and groups isn't ****i****m****p****l****e****m****e****nt****ed**** ****i****n**** ****the ****d****r****a****g****a****b****i****lity o****f the **various views.
- **P1 — Groups don't create a library item.** Grouping itself has now been located in the code, and that's also the right spot to hang group selection off the collections list column dropdown (see Open Questions). Still needs a library item created per group.
- **P2 — Make an icon for each of the apps** (ShowTools, BGTools, etc.).
- **P0 — "New Group from Selected" ignores the entered name.** The dialog asks for a name but doesn't use it — creates an "Untitled Show" instead.
- **P2 — Modified-click on archive names should jump directly into inline rename.**

## Selection & navigation

- **P0 — Clicking a collections list item moves the playhead; it should just select the list item.** Selecting should also make the list "hot" so up/down arrow keys navigate it. Opt-click can keep the current behavior of jumping the main viewer to the clicked image.
- **P1 — Frames-row position marker should be draggable with live scrub**, not just clickable.

## Transport & frames row bugs

- **P1 — Transport pane looks wrong in modes that don't use it.** Proposal: show the controls greyed out rather than hiding/breaking. Flagged as needing more design thought: what should happen if a file is dragged onto a greyed-out transport from a mode that isn't already showing a show on the timeline? (see Open Questions)
- **P0 — Out marker is misaligned**, sitting slightly left of the zone's actual end as drawn on the ruler.
- **P0 — Frames-row collapse handle drag doesn't track the mouse 1:1** — it moves roughly half the distance of the actual mouse travel.

## Ratings, hotkeys & Quick Show

- **P1 — Star rating show/hide, with a hotkey and a View menu entry.** Use Aperture's rating hot-key conventions as the reference for how ratings are applied and toggled.
- **P3 — Quick Show hasn't been touched yet** and needs scoping before CC can pick it up.

## BGTools integration

- **P1 — Launch BGTools from within ShowTools.** Add a BGTools menu in ShowTools for launching and installing it; consider a "Launch BGT when launching ShowTools" setting.
- **P1 — BGTools window should stay put when switching Spaces behind it.** That's the desired convenience behavior.
- **P0 — BGTools couldn't be self-quit during the last rebuild.** Both the app and its extension need investigation into quitting behavior.
- **P1 — Control Center launch icon requires two clicks to pop the quick panel** (should be one), and needs a better icon.
- **P1 — Per-screen stop, not just the master switch.** Keep the master switch at the top; add a per-monitor on/off toggle (color-coded green) in each monitor's title bar — or, alternatively, add a "Plays Nothing" entry to the list. Two possible mechanisms, pick one.
- **P0 — BGTools settings window opens on a monitor that's no longer connected**, unreachable, rather than the monitor it's launched from. Found 2026-09-25: unplugged a second monitor, then couldn't get to the window at all. Fix: always open centered on the calling monitor and its current Space; don't remember or restore the window's last closed position the way ShowTools' own windows do — a saved position can point at hardware that isn't there anymore. (This is the gap `spec/status.md`'s "Still needs Jason's hands" already flagged for W4 — built and checked on one monitor only, never tried with a second.)

## Show Similar & scale-to-fill

- **P3 — Show Similar's expected behavior is unclear**: is it backed by an API/model, and does it need the library scanned and analyzed first? Needs a spec before it can be evaluated. Is it analyzing the actual image or just the tags?
- **P3 — Large-library performance.** A \~4,000-image collection shows occasional sluggishness (though it's described as "surprisingly spry" overall, though no show was playing). Worth deciding whether a DB or indexing approach is needed to keep large libraries responsive as they grow.
- **P2 — Add a "scale to fill screen" option**, both as an effect in ShowTools and as a setting in BGT.
- **P1 — BGT needs pan & zoom, length, and transition options**, matching what ShowTools slides already offer.

## Open questions before CC can act

A few items need a decision or more detail before they're buildable, rather than being straightforward bug fixes:

1. **Greyed-out transport + drag target.** What should actually happen when a file is dragged onto a greyed-out transport in a mode that has no show loaded on the timeline yet? Needs a concrete interaction spec.
2. **Window-layer hierarchy.** Beyond fixing the inspector's immediate z-order bug, is a full documented layer hierarchy (and an audit of the other pop-out windows) worth doing now, or should it wait for a dedicated pass?
3. **Show Similar's engine.** Is this meant to call an external/local model API, or work off metadata already in the library? Determines whether a scan/index step is required first.
4. **Large-library scaling.** Is a DB/indexing layer worth building proactively, or should it wait until sluggishness becomes a real problem?
5. **Collections list column dropdown.** Needs a fuller design discussion. Group selection can live where grouping is already implemented, but the catalog pane — the file navigation list, now named "the catalog" to match the library-themed naming — also needs a list item per group. Worth a dedicated pass before CC builds it.

## Prioritized worklist for the next CC session

**P0 — do first (broken behavior):**

1. Collections column width/slide behavior on inspector close
2. Inspector panel z-order bug + define window-layer hierarchy, audit other pop-outs
3. Library pane background click should do nothing (currently changes to grid view)
4. No right-click response in main window background areas
5. "New Group from Selected" ignores the entered name, creates "Untitled Show"
6. Collections list item click moves playhead instead of selecting
7. Out marker misaligned on ruler
8. Frames-row collapse handle drag doesn't track mouse 1:1
9. Settings panel runs off the bottom of the screen
10. BGTools can't be self-quit
11. BGTools settings window opens on a disconnected monitor instead of the calling one (centered, no saved-position restore)

**P1 — core UX gaps:**

12. Groups don't create a library item (grouping itself is located; ties to item 38 below)
13. Collections closed-drawer state (stack against inspector)
14. Inspector header should sit at top of column when empty
15. Collections list minimum width too wide
16. Delete-from-library option when deleting a collection/group (as a checkbox in the dialog)
17. Reordering isn't implemented in the drag behavior of collections/groups views
18. Frames-row position marker: draggable + live scrub
19. Transport pane greyed-out state for unused modes
20. Star rating show/hide hotkey + View menu entry (Aperture conventions)
21. Launch BGTools from within ShowTools (menu + setting)
22. BGTools window persists across Space switches
23. Control Center launch icon: single-click + better icon
24. BGT per-screen stop (per-monitor toggle or "Plays Nothing" list entry — pick one)
25. BGT pan & zoom, length, and transition options

**P2 — polish:**

26. Remove rounded control containers in header bar; explore compact "Pro" look
27. App-wide corner-radius override
28. "Change Library" in library header right-click
29. App icons for each app
30. Frames row collapse to stacked handle
31. "Scale to fill screen" option (ShowTools effect + BGT setting)
32. Modified-click on archive names → inline rename

**P3 — needs a decision first (see Open Questions):**

33. Greyed-transport drag-and-drop interaction spec
34. Glass/vibrancy material check (dark mode confirmed opaque; light mode untested)
35. Show Similar's intended engine/scan requirement (image analysis vs. tags)
36. Large-library DB/indexing strategy (sluggishness happens even with no show playing)
37. Quick Show scope (not yet started)
38. Collections list column dropdown — group-selection placement + catalog pane list item
