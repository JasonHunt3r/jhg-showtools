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
| **⌘-click** | Add to or remove from the selection | Lane images, transitions and audio clips select one at a time (E4) | Built, where multiple selection exists |
| **⇧-click** | Select the range from the anchor (the last plain click or ⌘-click) to here, *replacing* the previous ⇧-range | — | **Settled** (Jason, 2026-09-24). Today the grid and the timeline only ever add to it (B3, E1). Lists already do it right |
| **Click on empty space** | Deselect all | — | Built in the grid |
| **Drag on empty space** | Rubber-band selection; ⌘ or ⇧ adds | The timeline: a drag on the ruler scrubs instead | Proposed (B4) |
| **Double-click** | **Go into it:** open the thing one level deeper | See "Double-click and ⌥-click" below | **Settled** as the meaning (Jason, 2026-09-24); some targets are still to be tried |
| **⌥-click** | The second meaning, where a thing has two | ⌥-click on a row handle already opens or closes every drawer | **Open** |
| **Right-click** | The commands for what's under the pointer, or for the selection if it's part of it (§3) | — | Built in some places; missing on lane images, transitions, markers (C1–C3) |
| **Hover** | A tooltip saying what it is, and its shortcut | — | Built for most controls |
| **Drag an item** | Move it: within an area it reorders; onto another area it adds or places there (§4) | A selected item drags the whole selection | Built |
| **Pinch** | Zoom the thing under the pointer (the timeline's scale, the viewer's work zoom) | — | Built |
| **Two-finger swipe** | Scroll, even over a window that's behind | The covered Timeline window's padding (`spec/windows.md`) | Built by macOS; the padding is Planned |

### Double-click and ⌥-click

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
  - the Library item in the sidebar: the library panel.
- **⌥-click (Open):** takes the other meaning where a thing has two. For
  example, if double-clicking a slide opens the inspector, ⌥-click opens
  the Slide Editor.

Today double-click toggles the inspector in Edit Slides and the browser,
and opens it (never closes it) in the timeline (G3).

## 2. Keys

| Key | Means, everywhere | Where it differs | State |
|---|---|---|---|
| **Delete** | Remove the selection from *where it is*: a slide from its show, a file from its collection, a lane item from its row. Asks first where the plan says so | In the Library (not a collection), a file goes to the Trash, after asking | Built for slides, the grid and the browser. The sidebar is missing (D1) |
| **⌘Delete** | Move to the Trash (delete from the library), without asking | In a collection it still asks, since it's more than leaving it | Built (settled, plan 2b) |
| **Esc** | Step back one level: close a drawer or popover, then clear the selection | In a text field, cancel the edit. In the player, leave full screen | Built partly; the timeline's Esc doesn't clear slides or a transition (E3) |
| **Return** | Do the default: OK in a dialog, commit a text field | On a selected item: rename it (Finder) | Built in dialogs; rename on Return **Settled** (Jason, 2026-09-24; B6, D4) |
| **Space** | **Play and pause, pretty much always** (Jason, 2026-09-24). Wanting to stop playback and having to juggle windows first would be confusing and frustrating | Never while typing in a text field. **Not Quick Look**, which departs from Finder on purpose: Quick Look is ⌘Y (Finder's other key for it) and double-clicking a tile. In Edit Slides, Space plays from the selected slide, and pauses what's playing | **Settled.** Built in Edit Show and the player |
| **← → ↑ ↓** | Move the selection; with ⇧, extend it | The timeline: by slide or by frame (E2, Open). The player: previous and next slide. The viewer with an image selected: nudge it | Built in lists, the player and the viewer; missing in the grid and the timeline (B2, E2) |
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
4. **Find it:** Show in Library, Show in Finder, Get Info.
5. **Remove it:** Remove from…, then Move to Trash… (destructive, last).

**Each target's core items** (Proposed; ✓ = there today):

| Target | Items |
|---|---|
| Library tile | New Show from ✓, Add to Show ✓, Show Similar ✓ · New Collection from ✓, Add to Collection ✓ · Show in Finder ✓, Rename… ✓, Get Info ✓ · Remove from Collection ✓, Move to Trash… ✓ |
| Slide (list or timeline) | Play from Here (✓ list only) · Duplicate ✓ · Show in Library, Show in Finder, Open Inspector · Remove from Show ✓ |
| Lane image | Duplicate · Show in Library, Show in Finder · Remove Image (C1) |
| Transition | its style (submenu), Use Show Default · Remove Transition (leaves a cut) (C2) |
| Audio clip | Detect Beats… ✓ · Show in Library, Show in Finder · Remove Audio Clip ✓ |
| Marker | Show or Hide Line · Remove Marker (C3) |
| Browser entry | Append (E) ✓, Insert at Playhead (W) ✓, Place in Images Row (Q) ✓ · Show in Finder ✓ · Remove from Collection ✓, Move to Trash… (today "Delete from Library…", C7) |
| Sidebar show | Play ✓, Play Full Screen ✓ · Duplicate Show · Export Show…, Export Movie… · Rename… ✓ · Delete Show… ✓ |
| Sidebar collection | New Show in… ✓ · Rename… ✓ · Delete Collection… ✓ |
| Sidebar Library | Import…, New Collection, Open Library Panel |
| An empty row | Place Image Here… ✓ (images row), Add Audio… (audio row) |

**One action, one name** everywhere: Move to Trash… (not "Delete from
Library…"); Remove from Show / Collection; Show in Finder; Show in
Library; Get Info.

## 4. Drops

| Drop onto | Does | State |
|---|---|---|
| The Library grid | Imports the files (from Finder or Photos) | Built |
| A collection's grid, or its sidebar row | Imports if they're from outside, then adds them to the collection | Built |
| A show's sidebar row | Appends pictures as slides (asks about any not in its collection) | Built; undoable since G1 |
| The slide list | Inserts where it lands, like the timeline | Proposed; today it appends (G2) |
| The timeline's slides row | Inserts where it lands; audio goes into the audio row at that time | Built |
| The images row | Places images at the drop time, end to end as room allows | Built |
| The audio row | Places audio at the drop time | Built |

Anything that adds files to a show asks first about files outside its
collection, unless the setting says always. (Built.)

## 5. The Edit menu

| Item | In the grid | In a show (either mode) | In a text field |
|---|---|---|---|
| Undo / Redo | the window's history | the window's history | the field's own |
| Cut / Copy / Paste | Copy: the files, for Finder or Mail (A3) | slides, with their settings (A3, Open: wanted?) | text |
| Duplicate ⌘D | — | slides; a selected lane image (A2) | — |
| Delete | as the Delete key | as the Delete key | text |
| Select All ⌘A | every tile in view (A1) | every slide (A1) | text |

All of these are Proposed except Undo, Redo and Delete, which are Built.

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

**The route, in the anatomy's order:**
1. **Sidebar:** the Library row, a collection row, a show row, empty
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
sidebar and grid menus that exist today (`MainView.swift`).
