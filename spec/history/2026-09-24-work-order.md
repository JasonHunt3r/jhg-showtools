# ShowTools work order — Jason's first-test notes (2026-09-24)

Written in the Claude app with Jason, from his notes on his first test and
a read of the repo at `6188a90`. **For Cloud Claude:** turn this into a
worklist for Claude Code on the Mac, and fold the decisions into the docs
they belong in. It isn't a build plan yet.

## How to use this

- **"Decided" is Jason's call.** Record it in the right spec as his, dated
  2026-09-24. Where it overturns wording already in a spec, change that
  wording. Each case is flagged below.
- **"For Cloud Claude" is context and open detail.** Where it says
  *propose*, write a proposal for Jason. Don't settle it yourself.
- **Check every code pointer against HEAD** before relying on it. They
  came from a read at `6188a90`, and `main` moves.
- The worklist goes into `spec/status.md`'s work queue in the usual form,
  one commit per item, and the BGTools items also go on `spec/bgtools.md`'s
  list. Order it least risky first, and name the hands-on check Jason does
  for each item.

## Already accounted for (no new work; listed so nothing doubles up)

- **New Collection opens the name dialog.** Built (`3984f4c`, audit H1).
  Jason's hands-on check is still outstanding.
- **Arrow keys to select several.** Settled in `conventions.md`: ⇧-arrows
  extend the selection. Queued as batch 4 (B2, E2).
- **A reusable window class for pop-out panes.** This is PaneKit
  (`spec/panekit.md`): pane ⇄ panel pop-out, built in, meant for reuse.
  The library-list use for filling a collection is `windows.md`'s library
  panel. The harness is already queued.

---

## Edit Show

### 1. The white bar (slide progress)

*Decided (Jason):* reverse it so it **fills left to right**, showing where
the playhead is within the current slide. Add a **setting that hides it**,
and a **right-click command** to switch it.

*For Cloud Claude:* it's `SlideProgress` in `EditShowView.swift`, and it
appears only in Edit Show's viewer. `plan.md` (Edit Show, Preview) says
the line "drains"; change that. The right-click command belongs on the
viewer's picture menu, which is stop 4 of the right-click route in
`conventions.md` and isn't settled yet. This becomes that menu's first
settled item. *Propose* whether the setting is saved with the show (like
the lines) or applies to the whole app. Keep its dim-when-paused look.

### 2. The range ends (I/O): drag, undo, lock

*Decided (Jason):* the I and O markers can be **dragged** on the ruler,
**⌘Z undoes** an errant drag, and they have a **locked/unlocked** state
so they can't be moved by accident.

*For Cloud Claude:* today a range end only answers a double-click (its
line toggle, `StorylineView.swift`, `rangeEnd`). There's no drag gesture.
**Overturns** `plan.md`: "It isn't undoable (undo keeps it as it is)".
Range edits become undoable. *Propose* where the lock lives (a right-click
on the range end, the range button, or both) and whether one lock covers
both ends. Locked ends should still take the I/O keys and ⌥X, since keys
are a deliberate act.

### 3. Undo a playhead jump

*Decided (Jason):* when a stray click on the ruler moves the playhead and
the area he was working on jumps out of view, **⌘Z puts back the playhead
and the view**.

*For Cloud Claude:* the view matters as much as the playhead. The harm is
losing your place, so the undo restores the timeline's scroll and zoom
too. The design risk: if every playhead move goes on the same undo stack
as edits, undoing a real edit means pressing ⌘Z through a pile of
playhead steps, which is why Final Cut doesn't do it. *Propose* (Jason's
wording favours plain ⌘Z): only a **ruler click that jumps** registers, not
playback, arrow nudges or J/K/L, and a scrub drag counts as one step.
**Consecutive jumps collapse into one step**, so ⌘Z always returns to
"where I was working". The fallback, if that can't be made clean: a
separate Go Back command with its own short history.

### 4. The range button

*Decided (Jason):* a **plain click** only shows or hides the range, as
now, keeping it without losing it. **⌥⌘-click** sets the range to the part
of the timeline in view. **⇧⌥⌘-click** sets it to the whole show, start to
finish, even where it's out of view.

*For Cloud Claude:* today the button is disabled when there's no range
(`EditShowView.swift`, the `.disabled` on `rangeIn`/`rangeOut`). It has to
be enabled for the modifier clicks. *Propose* what a plain click does with
no range set: stay inert, or act like ⌥⌘-click. A **locked** range refuses
both modifier clicks, with a beep. Modifier clicks are invisible, so the
two commands also go in the **Show menu** (beside Set Range In/Out) and on
the button's right-click. This follows the audit's F1 finding: every
command can be found in a menu.

### 5. Fill the range with images

*Decided (Jason):* **right-click the range ruler** → a dialog with an
**image picker** (a Library/Collection toggle; picking from the Library
also adds the pictures to the show's collection), a **transition**
dropdown, a **rhythm** setting, and **Replace / Displace**. It weighs the
range's length against the number of images, under the rhythm rules, and
lays the images across the range as slides.

- **Replace:** the slide the range starts inside is trimmed to end at the
  in point. The new slides fill the range. The slide the range ends inside
  is shortened at its front so it starts at the out point, and everything
  after the range **keeps its position** in time. Slides wholly inside the
  range are removed. The show's length doesn't change.
- **Displace:** the slide the range starts inside is trimmed to end at the
  in point, the same as Replace. Nothing inside the range is removed: the
  next slide and everything after it **move later**, starting where the
  imported run ends. The show gets longer.
- **Rhythm vs. image count:** a rhythm pattern runs for **as many notes
  as there are images**, one image per note, then stops. Patterns whose
  first N notes run longer than the range are **greyed out**, with the
  reason in their tooltip ("needs 14 s, the range is 10 s").

*For Cloud Claude:* build it from what exists. The picker is
`MultiItemPicker` (the empty-state buttons). The rhythm choices are the
apply sheet's own (`plan.md`, "The apply sheet": roughly N beats per slide,
a change every roughly X seconds, a rhythm pattern from the Rhythm tool),
plus **Even**, an equal split and the default. The other modes follow the
same rule as patterns: one slide per image, with values that would
overrun the range greyed out. Even always fits. With a detected song
under the range, changes quantize onto its beats as the apply sheet
does. Keep the plan's rule "slides are never split": these are trims, and
a trimmed slide keeps its settings. The whole fill is **one undo step**.
A locked range can still be filled, since the ends don't move. This is
the ruler's first right-click item (stop 7 of the right-click route).

*Propose:*
- a run *shorter* than the range: extend the last slide to the out point,
  so the range is always exactly filled and Replace's "everything after
  keeps its position" holds;
- a preview line in the dialog before OK: the count, each slide's length,
  and whether the run fills the range.

*Confirm with Jason:* in Displace, the first slide's trimmed-off tail is
simply dropped, not moved after the run. (This was App Claude's reading,
not his words.)

---

## BGTools (also add to the list in `spec/bgtools.md`)

### 6. A Quit you can find

*Jason:* BGTools needs a way to quit. Quit exists today, but only as the
last item in the settings window's ⋯ toolbar menu (`MainWindow.swift`),
and he didn't find it.

*For Cloud Claude:* add Quit to the floating panel, and make **⌘Q** work
while the settings window is open, since the app is a regular app then
(`BGToolsApp.swift`, the activation-policy switch). Quitting stops every
desktop show, so the panel's item should say so, e.g. "Quit BGTools
(stops desktop shows)".

### 7. All same → Synchronize

*Decided (Jason):* rename **All same** to **Synchronize**: the switch, its
row, its help text, the note shown on a screen while it's on, and the
panel. Update `bgtools.md`'s settled wording (question 2). The setting's
key in the settings file can keep its name if renaming it would need a
migration. Say which in the commit.

### 8. Naming screens

*Decided (Jason):* each monitor gets a **name of your own**, like **Work
Monitor**, shown with a **small tag of macOS's model name** (PA279CRV) so
the physical screen is always identifiable. Unnamed screens show the
model name, as now.

*For Cloud Claude:* key names by display uuid, as settings already are
(`bgtools.md`, "Key Spaces by uuid, never by id"). Names show everywhere a
screen appears: the settings window, the panel, logs. *Propose* whether
Spaces get names too (e.g. "Work Monitor · Mixing"), or only monitors.

### 9. Arrangement: a map as well as the stack

*Decided (Jason):* add a **spatial view** showing the monitors laid out
as they sit on the desk (like System Settings ▸ Displays), with each
monitor's Spaces inside it. **Keep the stacked list too**, since it's
better in some situations. They're two views of the same settings.

*For Cloud Claude:* `NSScreen.frame` gives the arrangement. *Propose*
how to switch views (a segmented control above the list?) and whether
the choice is remembered.

### 10. The window opens on your screen, showing your screen

*Decided (Jason):* the full settings window opens **on the monitor it was
called from**, with **that monitor's current Space already selected**.
The panel can still select and change any screen.

*For Cloud Claude:* today the window calls `center()` (the main screen)
with a frame autosave (`BGToolsApp.swift`), and nothing is preselected.
"Called from" means the screen with the pointer when opened from the
panel or a Control Center tile. *Propose* what happens when the window
is already open on another monitor: move it, or stay put and just change
the selection.
