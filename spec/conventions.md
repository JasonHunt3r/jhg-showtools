# Conventions — what each gesture means, everywhere

**Status:** Draft, 2026-09-24. Nothing new is built. Each row is marked:
- **Built**: it works this way today.
- **Settled**: Jason has decided it, and it's not built yet.
- **Proposed**: Claude's suggestion, awaiting Jason.
- **Open**: to be decided, often by trying it.

The audit (`spec/hig-audit.md`) lists what's missing. This file says what
it should be, so each fix builds toward one rule instead of deciding for
itself. Names follow `spec/anatomy.md`.

**Two kinds of convention** (`spec/how-we-design.md`):
- **Universal:** what every Mac app does. Sections 1–7 below. These can
  be written ahead of time.
- **Contextual:** what *this* app should do, found by using it. Section 8
  is their log, added to as Jason makes real shows.

## The ground rules

1. **Strive for one language, and deviate where that's clearer**
   (Jason, 2026-09-24). An action should usually mean the same thing
   wherever it's offered. It changes where a different behaviour is what
   people expect, or is more intuitive in that place. This is a leaning,
   not a law: there will be exceptions, and it mustn't be applied heavy-
   handedly.
   - **Who decides:** Jason judges the deviations, since he uses the
     software. Claude's part is to point out where a choice departs from
     the HIG or from tradition (Finder, Photos, Final Cut), so each
     departure is made knowingly.
   - Edit Slides and Edit Show are the first test case (audit §G).
2. **Everything can be found without a manual.** Every control has a
   tooltip, every command has a menu item showing its shortcut, and
   every right-click offers what's under the pointer.
   (Today: 78 tooltips, and Edit Show's commands are in no menu, F1.)
3. **Every change is one undo step,** with a name in Edit ▸ Undo. Drags
   commit once, on release. Viewing isn't changing: zoom, scroll,
   selection and panels aren't undone. (CLAUDE.md; G1 fixed the three
   adds that weren't recorded.)
4. **A button means what it says.** Cancel means never mind, and leaves
   nothing behind. Nothing is Untitled unless someone clicked OK on it.
   (Settled, H1.)
5. **Destructive actions come last and ask first,** except where a
   modifier says "I'm sure" (⌘Delete). (Settled, plan 2b.)

## 1. Pointer

| Gesture | Means, everywhere | Where it differs | State |
|---|---|---|---|
| **Click** | Select this, and only this. Takes the keyboard to that area | — | Built (grid, timeline, lists) |
| **⌘-click** | Add to or remove from the selection | — | Built in the grid, lists and the slides row. **Settled for lane images and audio clips too** (Jason, 2026-09-24; E4): today they select one at a time |
| **⇧-click** | Select the range from the anchor (the last plain click or ⌘-click) to here, *replacing* the previous ⇧-range | — | **Settled** (Jason, 2026-09-24). Today the grid and the timeline only ever add to it (B3, E1). Lists already do it right |
| **Click on empty space** | Deselect all | — | Built in the grid |
| **Drag on empty space** | Rubber-band selection; ⌘ or ⇧ adds | The timeline: a drag on the ruler scrubs instead | **Settled** (Jason, 2026-09-24; B4) |
| **Double-click** | **Go into it:** open the thing one level deeper | See "Double-click" below | **Settled** as the meaning (Jason, 2026-09-24); some targets are still to be tried |
| **⌥-click** | Jason's leading idea: **select the thing behind** in an overlap, such as the slide under a transition or a lane image | ⌥-click on a row handle already opens or closes every drawer. ⌥-drag copies (§1 note) | **Open**. See "How ⌥ is used elsewhere" below |
| **Right-click** | The commands for what's under the pointer, or for the selection if it's part of it (§3) | — | Built in some places; missing on lane images, transitions, markers (C1–C3) |
| **Hover** | A tooltip saying what it is, and its shortcut | — | Built for most controls |
| **Drag an item** | Move it: within an area it reorders; onto another area it adds or places there (§4) | A selected item drags the whole selection | Built |
| **Pinch** | Zoom the thing under the pointer (the timeline's scale, the viewer's work zoom) | — | Built |
| **Two-finger swipe** | Scroll, even over a window that's behind | The covered Timeline window's padding (`spec/windows.md`) | Built by macOS; the padding is Planned |
| **Double-click an edge handle** | Open or close its pane (Jason, 2026-09-24) | — | Settled; handles are Planned (`spec/windows.md`) |
| **Drag an edge handle** | Open the pane to a width, or resize it | — | Settled; Planned |
| **⌘⌥-click a timeline row** | Open that row's drawer | ⌥-click on a row *handle* opens or closes every drawer | Settled (Jason, 2026-09-24); not built |

### How ⌥ is used elsewhere (for deciding ⌥-click)

What's well established on the Mac and in creative apps:
- **⌥-drag copies instead of moving:** Finder, Keynote, Final Cut, and
  most editors. This is the strongest convention for ⌥ with the mouse,
  and **proposed here: ⌥-drag a slide, lane image or audio clip to
  duplicate it** there.
- **⌥ widens a click to "all of them":** ⌥-click a disclosure triangle
  opens every nested one; ⌥-click a window's close button closes all of
  the app's windows. The row handle's ⌥-click (every drawer) already
  follows this.
- **⌥-click sets a point:** Photoshop's Clone Stamp sets its source with
  ⌥-click. It's a precedent for **aiming Pan and Zoom's zoom-to point**
  by ⌥-clicking the image (plan, Later).
- **Selecting what's behind:** design apps mostly use ⌘-click
  (Illustrator's "select behind"), or a right-click menu listing
  everything under the pointer (Photoshop, Figma). In ShowTools ⌘-click
  already means "add to the selection", so **⌥-click for "behind" would
  be a knowing departure.** A right-click "Select" submenu of what's
  under the pointer could do the same job without taking ⌥.

**Final Cut's ⌥-click (checked 2026-09-24):** in Final Cut, a plain click
on a clip only moves the *skimmer*, and **⌥-click moves the playhead** to
that frame (and selects the clip if skimming is off). ⌥⌘-click moves a
connected clip's connection point. In ShowTools a plain click on a block
already moves the playhead to it, so Final Cut's ⌥-click meaning is
already the plain click here, and **⌥-click is free for something
else**, such as selecting what's behind.

### Double-click

**Settled (Jason, 2026-09-24): double-click means "go into it"**, and
every item below is a double-click action. Where a target lists two
candidates, real testing picks one:
- **Double-click: open the thing one level deeper.**
  - a collection row: open its disclosure (Jason's original idea);
  - a Library tile: Quick Look, or Get Info (B6). Quick Look is the
    natural one, now that Space is play/pause (§2);
  - a slide, in either mode: the Slide Editor, or the inspector (G3);
  - a lane image or transition: its settings bar, or the Slide Editor;
  - a row's handle or title: the row opened up (`spec/windows.md`);
  - the Library item in the Library pane: the library panel.
- **⌥-click (Open):** takes the other meaning where a thing has two. For
  example, if double-clicking a slide opens the inspector, ⌥-click opens
  the Slide Editor.

Today double-click toggles the inspector in Edit Slides and the browser,
and opens it (never closes it) in the timeline (G3).

## 2. Keys

| Key | Means, everywhere | Where it differs | State |
|---|---|---|---|
| **Delete** | Remove the selection from *where it is*: a slide from its show, a file from its collection, a lane item from its row. Asks first where the plan says so | In the Library (not a collection), a file goes to the Trash, after asking | Built for slides, the grid and the browser. The Library pane is missing (D1) |
| **⌘Delete** | Move to the Trash (delete from the library), without asking | In a collection it still asks, since it's more than leaving it | Built (settled, plan 2b) |
| **Esc** | Step back one level: **close the Slide Editor** (Jason), a drawer or a popover; then clear the selection | In a text field, cancel the edit. In the player, leave full screen | Built partly. Little use for it yet (Jason, 2026-09-24): more cases will turn up with use, and go in §8 |
| **Return** | Do the default: OK in a dialog, commit a text field | On a selected item: rename it (Finder) | Built in dialogs; rename on Return **Settled** (Jason, 2026-09-24; B6, D4) |
| **Space** | **Play and pause, pretty much always** (Jason, 2026-09-24). Wanting to stop playback and having to juggle windows first would be confusing and frustrating | Never while typing in a text field. **Not Quick Look**, which departs from Finder on purpose: Quick Look is ⌘Y (Finder's other key for it) and double-clicking a tile. In Edit Slides, Space plays from the selected slide, and pauses what's playing | **Settled.** Built in Edit Show and the player |
| **← → ↑ ↓** | Move the selection; with ⇧, extend it | **The timeline (settled, Jason, 2026-09-24):** ← → move through the items in the current row (slides, or audio clips); ↑ ↓ move between rows; **in the ruler**, ← → nudge the playhead. The player: previous and next slide. The viewer with an image selected: nudge it | Built in lists, the player and the viewer; missing in the grid and the timeline (B2, E2) |
| **Home / End** | The first or last item, or the show's start or end | — | Built in the player |
| **Tab** | Move the keyboard to the next area | — | Built by SwiftUI where areas are focusable |
| **Single letters** | Final Cut's keys, where there's a timeline: J K L shuttle, I O range, M marker, N snapping; E W Q add from the browser | Never while typing in a text field (`SingleKeys`) | Built; shown in no menu (F1) |

## 3. Right-click menus

**Draft, to be discussed.** Right-click is highly contextual, and a
little global (Jason, 2026-09-24), so it gets its own conversation, area
by area. The plan for it is at the end of this file. What follows is
Claude's starting draft for that conversation, not a decision.

**A starting order,** proposed for every menu. Groups are separated by a
divider, and empty groups are skipped:

1. **Go / play:** Play from Here, Show Similar, Open (whatever
   double-click does).
2. **Make and add:** New Show from…, Add to Show, Add to Collection,
   Duplicate.
3. **Change it:** its own settings (a transition's style, Detect Beats…,
   Show or Hide Line).
4. **Find it:** Show in Library, Get Info. (Show in Finder only for a
   library's own location; see the rule below the table.)
5. **Remove it:** Remove from…, then Move to Trash… (destructive, last).

**Each target's core items** (Proposed; ✓ = there today):

| Target | Items |
|---|---|
| Library tile | **Settled 2026-09-24.** Play (the selection, or one picture; greyed out until playing without a show is built), Quick Look (⌘Y), Show Similar ✓ · New Show from *N* Items… ✓ (opens the New Show panel), Add to Show ✓ · New Collection from ✓, Add to Collection ✓ · Copy · Rename… ✓, Get Info ✓ · Remove from Collection ✓, Move to Trash… ✓ |
| Find Similar Images set header (was Group Similar) | **Settled 2026-09-24.** Select Group, Keep One… ✓, **Keep as Group** · New Show from Group…, Add Group to Collection ▸ |
| Library pane: a group | *To settle with groups* (`spec/plan.md`, "Groups inside collections"). Drop files onto it; it lists beside the collection's shows |
| Empty grid space | **Settled 2026-09-24.** Import…, Select All, New Collection |
| Slide (list or timeline) | **Settled for Edit Slides, 2026-09-24.** Play from Here ✓, Play Full Screen (from the slide) · Duplicate ✓, Copy, Paste (**with ⌥ held: Copy Settings, Paste Settings**) · **Replace Image…** · Show in Library, Open Inspector · Remove from Show ✓. No Show in Finder. **Quick settings as submenus** (settled): Length ▸, Transition ▸, Pan and Zoom ▸, each applying to every selected slide as one undo step |
| Edit Slides: empty list space | **Settled 2026-09-24, to try.** Add from Collection…, Import…, Paste, Select All (today it shows the slide menu with nothing to act on) |
| Edit Slides: the defaults bar | **Settled 2026-09-24, to try by hand.** Use Defaults for All Slides (clears each slide's own values), Save as Preset… (the New Show presets), Reset to App Defaults |
| Viewer: a slide's image in the picture | **Settled 2026-09-24.** Open in Slide Editor (greyed out until built), Show in Library · Length ▸, Transition ▸, Pan and Zoom ▸ (the slide list's quick settings) · Reset Transform, Rotation Handles on/off · **Select ▸** (everything under the pointer, e.g. a lane image and the slide beneath) |
| Viewer: the pasteboard (the grey round the picture) | **Settled 2026-09-24.** Work Zoom ▸ (Fit, 75 %, 50 %), Onion Skin on/off, Pop Out Viewer |
| Viewer: the frame strip | **Settled 2026-09-24.** Play from Here, Follow Timeline / Whole Show, Hide Frame Strip |
| Lane image | Duplicate, **Replace Image…** · Show in Library · Remove Image (C1) |
| Transition | its style (submenu), Use Show Default · Remove Transition (leaves a cut) (C2) |
| Audio clip | Detect Beats… ✓ · Show in Library · Remove Audio Clip ✓ |
| Marker | Show or Hide Line · Remove Marker (C3) |
| Browser entry | **Settled 2026-09-24.** Append to Show (E) ✓, Insert at Playhead (W) ✓, Place in Images Row at Playhead (Q) ✓; for an audio file, **Place at Playhead** · for a *use* (an entry under "In this show"): Select in Timeline, Play from Here · Show in Library · Remove from Show (that use only), Remove from Collection ✓, **Move to Trash…** (was "Delete from Library…", C7). The letters show as shortcuts at the menu's right edge, if that can be done without E, W and Q taking typing from Search; otherwise they stay in the titles (C8) |
| Inspector: a section header | **Settled 2026-09-24.** Reset Section to Show Default · Copy Section Settings, Paste Section Settings |
| Inspector (anywhere, for its slide) | **Settled 2026-09-24.** Replace Image… (others to settle) |
| Browser: empty space | **Settled 2026-09-24.** Import…, Add from Library… |
| Library pane: a show | **Settled 2026-09-24.** Play ✓, Play Full Screen ✓, Play on Desktop · Duplicate Show · Export ▸ (Show…, Movie…) · Rename… ✓ · Delete Show… ✓ |
| Library pane: a collection | **Settled 2026-09-24.** Play (greyed out until playing without a show is built) · New Show in… ✓ · Rename… ✓ · Delete Collection… ✓ |
| Library pane: the Library row | **Settled 2026-09-24.** Import…, New Collection, Open Library Panel · Show in Finder (the library's folder) |
| An empty row | Place Image Here… ✓ (images row), Add Audio… (audio row) |

**Show in Finder is for a library's location only** (Jason, 2026-09-24).
It's on the Library row, and in Settings, which is useful when there
are several libraries. **Files never get it:** the library holds its own
copies, and where the originals went is unknown, so revealing a file
shows nothing useful. So it's off the tiles, slides, lane images, audio
clips and the browser, which have **Show in Library** instead. (Jason
said so for tiles and slides; the rest follow the same reasoning.)

**One action, one name** everywhere: Move to Trash… (not "Delete from
Library…"); Remove from Show / Collection; Show in
Library; Get Info.

## 4. Drops

| Drop onto | Does | State |
|---|---|---|
| The Library grid | Imports the files (from Finder or Photos) | Built |
| A collection's grid, or its row in the Library pane | Imports if they're from outside, then adds them to the collection | Built |
| A show's Library pane row | Appends pictures as slides (asks about any not in its collection) | Built; undoable since G1 |
| The slide list | Inserts where it lands, like the timeline. **Dropped onto a slide:** offers Replace or Insert (settled 2026-09-24, Replace Image…) | **Settled** (Jason, 2026-09-24); today it appends (G2) |
| The timeline's slides row | Inserts where it lands; audio goes into the audio row at that time. **Dropped onto a slide:** offers Replace or Insert (settled 2026-09-24) | Built |
| The images row | Places images at the drop time, end to end as room allows | Built |
| The audio row | Places audio at the drop time | Built |

Anything that adds files to a show asks first about files outside its
collection, unless the setting says always. (Built.)

## 5. The Edit menu

| Item | In the grid | In a show (either mode) | In a text field |
|---|---|---|---|
| Undo / Redo | the window's history | the window's history | the field's own |
| Cut / Copy / Paste | Copy: the files, for Finder or Mail (A3; wanted if it's easy, and it is: see below) | **slides with their settings and effects, from one show to another** (A3, settled wanted) | text |
| Paste Settings ⇧⌘V | — | Proposed: paste the copied slide's settings and effects onto the selected slides, like Final Cut's Paste Attributes | — |
| Duplicate ⌘D | — | slides; a selected lane image (A2) | — |
| Delete | as the Delete key | as the Delete key | text |
| Select All ⌘A | every tile in view (A1). **Top priority** (Jason: hand-clicking 4,000 test images) | every slide (A1) | text |

Undo, Redo and Delete are Built. Copy and Paste of slides and ⌘A are
wanted (settled 2026-09-24); the rest is Proposed.

**Copying tiles to Finder or Mail is small:** the files' URLs go on the
pasteboard, and Finder pastes copies. Photos is different: **native
access to the Photos library** (browsing it inside ShowTools, plan,
Later) is the larger job, but **it doesn't need the paid developer
membership** (checked 2026-09-24). ShowTools is signed ad hoc, with no
team, no hardened runtime and **no sandbox** (`project.yml`; only the
Control Center tiles are sandboxed). For an app like that, Photos'
framework needs only a usage line in Info.plist
(`NSPhotoLibraryUsageDescription`) and the user's permission. The
photos-library entitlement matters only to a sandboxed or hardened app,
and it isn't one of the restricted entitlements that need a paid
account. The $99 membership is for distributing (notarizing, the App
Store), not for this.
- *The practical catch:* macOS ties the permission to the app's
  signature, and an ad-hoc signature changes with every build, so macOS
  may ask again after each rebuild, as it can for Accessibility. Signing
  with a free Apple ID ("Personal Team" in Xcode) gives a stable
  identity, and costs nothing. Worth confirming on the Mac.

## 6. Dialogs and naming

- **The default button** is the one that does the thing (Make Show,
  Import, Move to Trash), and Return presses it. Cancel is Esc. (Built:
  11 dialogs set both.)
- **Nothing is made until OK.** New Collection and New Show ask first,
  with a suggested name already selected (settled, H1). New Show's
  dialog is the settings panel (`spec/simple-things-fast.md`).
- **Destructive buttons say what they do:** "Move 3 Items to Trash", not
  "OK". (Built.)
- **A notice that can be turned off** has "Do not show this message
  again", and a way back in Settings. (Built: the slide-removal notice.)

## 7. Windows

What a window does follows its job (`spec/windows.md`):
- **Panels float:** the library and the inspector.
- **Ordinary windows can go behind:** the Timeline window.
- **Windows tied to playback follow the show** (the timeline, the viewer);
  **sources don't** (the library).
- **Launch puts everything back** where it was, except perhaps the
  playhead.
- **⌘Z in any of the app's windows** undoes the main window's history.

## 8. Contextual conventions (found by use)

Each entry says what happened, and the rule it became.

| Found | What happened | The convention |
|---|---|---|
| 2026-09-24, first real show | New Show from a selection made twenty 5-second dissolves without asking, and the fix (the defaults bar) wasn't discoverable | **Anything that makes several things at once asks for their settings first.** The New Show panel |
| 2026-09-24 | A new collection gave no hint of how to fill it, short of a small, far-away Import button or a small drop target | **A container you're meant to fill shows how, front and centre** (H2). A floating library over it gives a big drop target |
| 2026-09-24, planning windows | The library window shouldn't jump around with whatever image is playing, but a file used in a show still needs a way back to the library | **Anything that uses a file can take you to it, on request:** Show in Library, which opens the library and selects it |
| 2026-09-24 | Pan and Zoom only zoomed, and aiming it meant dragging a small frame | **Aim at the picture itself:** click, or ⌥-click, on the image (plan, Later) |

## Plan: the right-click conversation (next session)

Jason's plan (2026-09-24): after a clear, go through right-click menus
**area by area, using `spec/anatomy.md` as the guide.** Finish the other
universals first.

**For each area, three questions:**
1. **What's under the pointer?** Each thing that can be right-clicked in
   that area, including empty space.
2. **What's global?** Items that belong in every menu, or in every menu
   of a kind (e.g. Show in Library on anything that uses a file).
3. **What's contextual?** Items only this thing, in this place, needs.
   Then the order.

**Progress:**
- **1. The Library pane: done 2026-09-24.** Jason's answers:
  - **The Library row** gets **Show in Finder**, which reveals the
    library's folder ("would be nice").
  - **Playing a collection without making a show** goes on the
    collection's menu now, **greyed out until it's built**
    (`spec/simple-things-fast.md`, Quick Show).
  - **Duplicate Show and Play on Desktop:** both wanted. They're the two
    items here that need new code, not just a menu item. Play on Desktop
    hands the show to BGTools (`spec/bgtools.md`).
  - **Export:** in the show's menu **and** in File ▸ Export, as one
    **Export ▸** submenu (Show…, Movie…) wherever export appears. The
    File menu's two Export items become that submenu too.
  - **Anything reached for and not found:** nothing yet; there hasn't
    been enough use. It goes in §8 when it happens.
- **2. The Library grid: done 2026-09-24.** Jason's answers:
  - **Play** goes on the tile menu too, greyed out until it's built, for
    a selection **and for a single picture**: a show from one image is
    wanted (below).
  - **Quick Look (⌘Y) and Copy** go on the tile menu.
  - **New Show from *N* Items…** keeps the count in its name, and opens
    the New Show panel.
  - **The Group Similar header** gets Select Group, New Show from Group…
    and Add Group to Collection ▸, beside Keep One….
  - **Empty grid space** gets Import…, Select All and New Collection.
  - **Anything reached for and not found:** nothing yet.
  - **A show from one picture** (Jason): one image, with audio, moving
    all the time in Pan and Zoom, dissolving into another move of itself.
    *From the code:* the model already allows it. A slide is one use of
    a file, the same file can be many slides, and Auto picks a different
    move per slide (seeded by the slide's id). So it's the one picture as
    several slides, each on Auto, with dissolves between them. Playing a
    single tile builds exactly that. Recorded in
    `spec/simple-things-fast.md`.
- **Groups inside collections** (Jason, 2026-09-24): raised here, to be
  built right away: `spec/plan.md`, "Groups".
- **3. Edit Slides: done 2026-09-24.** Jason's answers:
  - **Play:** Play from Here, and **Play Full Screen** (from the selected
    slide).
  - **Copy and Paste** of slides on the menu; **Copy Settings and Paste
    Settings** appear **only while ⌥ is held**. They swap in and out live
    as ⌥ is pressed and let go with the menu open. That's AppKit's
    *alternate* menu items (as Finder's File menu does with Close and
    Close All): an `NSMenuItem` marked alternate, with the ⌥ modifier.
    SwiftUI's context menus may not offer it, so the build may need an
    AppKit menu here.
  - **Show in Library** yes. **Show in Finder** no: the file was copied
    into the library, and where the original went is unknown, so there's
    nothing useful to reveal.
  - **Empty list space:** Add from Collection…, Import…, Paste, Select
    All. Try it.
  - **The defaults bar:** Use Defaults for All Slides, Save as Preset…,
    Reset to App Defaults. Sounds good; to be tried by hand.
  - **Anything missing:** nothing yet.
  - **Quick settings as submenus** ("that'll be nice"): Length ▸ (3 s,
    3.5 s, 5 s, 8 s, Show Default, Custom…), Transition ▸ (the styles, Show
    Default), Pan and Zoom ▸ (Off, Auto, Show Default). Each applies to
    every selected slide in one undo step. Custom… opens the inspector on
    that setting.
- **4. Edit Show, the viewer: done 2026-09-24.** Jason said yes to all:
  - **A slide's image:** Open in Slide Editor (greyed out until built),
    Show in Library, the quick-settings submenus, Reset Transform,
    Rotation Handles on/off.
  - **Select ▸** lists everything under the pointer (a lane image, the
    slide beneath). It does the "select what's behind" job, so ⌥-click
    stays free (§1).
  - **The pasteboard:** Work Zoom ▸, Onion Skin, Pop Out Viewer.
  - **The frame strip:** Play from Here, Follow Timeline / Whole Show,
    Hide Frame Strip.
  - **Anything missing:** nothing yet.
- **5. Edit Show, the browser: done 2026-09-24.** Jason's answers:
  - **Tidied by the rules:** the add items first, Show in Library, then
    Remove from Collection and **Move to Trash…** last. No Show in Finder.
  - **The letters (E, W, Q)** show as shortcuts at the right edge, if that
    can be done without them taking typing from Search.
  - **A use** gets Select in Timeline, Play from Here, and Remove from
    Show (that use only).
  - **An audio file** gets **Place at Playhead**. It doesn't need to say
    "audio row"; people know where audio goes.
  - **Empty space:** Import…, Add from Library….
- **Replace Image…** (Jason, 2026-09-24, raised here): on a slide and a
  lane image, to swap which picture it uses and keep its settings
  (`spec/plan.md`, Later).
- **6. The inspector: in progress 2026-09-24.**
  - **A section header** (Transform, Effects, Sound…): **Reset Section to
    Show Default**, and **Copy / Paste this section's settings** (for
    example one slide's Transform onto others). Settled.
  - **Replace Image…** on the inspector's right-click menu. Settled.
  - Still to answer: Reset to Default on a single control; the header
    bar's menu; anything reached for and not found.

**The route, in the anatomy's order:**
1. **Library pane:** the Library row, a collection row, a show row, empty
   space.
2. **Library grid:** a tile, several selected tiles, a Group Similar
   group's header, empty space, the filter bar.
3. **Edit Slides:** a slide row, several rows, the defaults bar, empty
   space.
4. **Edit Show, the viewer:** the picture (with or without an image
   selected), the pasteboard round it, the frame strip.
5. **Edit Show, the browser:** a use, a file not in the show, a section
   header.
6. **The inspector:** a section header, a control.
7. **The timeline pane:** the transport, the ruler (with markers and the
   range), a row handle, and each row:
   - images row: a lane image, empty space;
   - transitions row: a transition, a cut without one;
   - slides row: a block, several blocks, a cut;
   - audio row: an audio clip, empty space.
8. **Windows around the main one:** the player, the pop-out viewer, the
   Info panel, the Rhythm tool, and (planned) the library panel and the
   Slide Editor.

**Bring to it:** §3's draft order and table, the audit's C1–C8, and the
Library pane and grid menus that exist today (`MainView.swift`).
