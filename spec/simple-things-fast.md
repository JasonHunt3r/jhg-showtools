# Simple things fast

**Status:** Planned: ideas, not yet designed (Jason, 2026-09-22 and
2026-09-24). Nothing is built. Jason has answered the first round of
questions (below). **Confirmed 2026-09-25: all three answers (the guided
first run, Quick Show, and the levels) are to be built, not chosen
among** — they work together, per "Three answers, which work together"
above. **Left:** the one still-open question below, the Quick Show
dialog's details, then a design with Jason.

Names follow `spec/anatomy.md`. This was called "a simple way in" in the
plan and status. Jason's own framing is the better name: the app does a
lot, but it doesn't do simple things fast.

## The problem (Jason, 2026-09-24)

The editor was designed to be deep, and it is. But making the first real
show made two things plain:

- **Simple things aren't fast.** Getting from a folder of photos to a
  slideshow playing takes a long run of steps.
- **With every window open, it's a lot to take in.** Every area shows at
  once, whatever the job in hand.

## Design posture: the six essentials (Jason, 2026-09-24)

A slideshow is six things: **the pictures, their order, how long each
shows, how one gives way to the next, whether they move, and what plays
under them.** Everything else in the app refines one of them.

**Perceptual efficiency** is the posture that follows. Wherever someone
starts (Quick Show, New Show…, BGTools, Basic), the six come first, in
that order, and nothing else is in the way. The refinements (transforms,
the lane, effects, rhythm, markers) are there when asked for, never in
front. A new panel or level is checked against the six: which of them
does it serve, and does it put anything ahead of them?

## The principle (Jason, 2026-09-24)

The app should work intuitively, in its own plain vocabulary, so most
people can figure it out. Even the full tools should be a matter of
tooltips and trial and error. The first run, Quick Show and the levels
are there to make the first minutes fast, not to replace that.

## Three answers, which work together

### 1. A guided first run

Each first encounter teaches itself and nudges to the next step. It
already has its own brief, `spec/first-run-brief.md`, where Jason's
draft wording from 2026-09-24 now lives. The sequence is:

1. The empty library welcomes you.
2. You add files.
3. **My First Collection**: name it and fill it.
4. A nudge into the first show.

### 2. Play without building: Quick Show

**The goal (Jason):** open the app and have a slideshow going in a few
seconds. Open the app, click the play triangle, click a few things, drag
a slider or type a value, and press Return to start.

**The Quick Show dialog.** Play with no show selected opens it. Every
field starts filled in, so Return alone plays:
- **Pool:** the Library, a collection, or a show.
- **Order:** in order, or randomized.
- **Pan and Zoom:** on or off.
- **Length** of each slide.
- **Transition** and its duration.
- **Audio:** an audio file, or a playlist, if wanted.
- **Play** (Return), full screen or in a window.
- **Send to BGTools:** plays it on the desktop instead. Quitting
  ShowTools leaves it running, since BGTools is a separate app that
  keeps going on its own (`spec/bgtools.md`).
  - *From the code:* BGTools already has pools as play modes (a show in
    order, a show shuffled, random from a collection, a random show,
    random from all files), plus one set of desktop defaults (length,
    transition, Pan and Zoom, fit). Send to BGTools is mostly handing it
    the dialog's choices.
  - *What's new:* BGTools' random modes play pictures only. Audio chosen
    in the dialog would be a new thing for it to play. And its defaults
    are shared by every random mode, so a Quick Show sent with its own
    length or transition needs somewhere of its own to keep them.

**Playing a show, or only its pictures (Jason).** With a show as the
pool, the dialog plays it one of two ways:
- **The show as built:** its own lengths, transitions, lane and audio.
  The dialog's picture settings are greyed out, since the show decides.
- **Images only:** a checkbox. The dialog's settings are active, and they
  draw only the show's *pictures*, not its composition. It's the same as
  picking a collection, with the show's pictures as the pool.

**It remembers (Jason).** The dialog opens on its last settings, so
Return plays the same thing again. **Presets** hold favourite settings,
with an **Add Preset** button to save the current ones under a name.

**Audio (Jason):** a single audio file or a playlist, with a **Loop**
checkbox. A playlist is new to the app: several audio files played one
after another.

**The Rhythm tool is available here too (Jason).** In a show, it places
slides on the beat (`RhythmPanel`). In Quick Show it would time the
slide changes to the chosen audio's beats, using a saved rhythm pattern
(patterns are already saved by name in the library,
`AppModel.saveRhythmPattern`). *From the code:* the tool is built around
one show (`RhythmTool.open(showID:)`) and writes slide lengths into it.
A Quick Show isn't a saved show, so the tool would work on the
in-memory one. It's the same seam as playing without building.

**A show from one picture (Jason, 2026-09-24).** One image, with audio,
moving all the time, and dissolving into another move of itself. Play on
a single tile, or a Quick Show whose pool is one picture, makes it.
*From the code:* nothing new in the model. The one file becomes several
slides (a slide is a *use* of a file), each with Pan and Zoom on Auto,
which picks a different move per slide (seeded by the slide's id), with
dissolves between them, looping. How many slides, and how long each, are
the dialog's length and the audio's length.

**Other ways in**, which the dialog complements:

- **Play the Library, a collection, or a selection in the grid.** It
  plays at once with the app's defaults (length, transition, fit), in
  grid order, as the Play command's own player window does for a show.
  Today only a show can be played (`Player.open` takes a `Show`).
- **Keep it if you like it.** The player offers **Save as Show…**. That
  asks for a name (audit H1: nothing is Untitled unless OK'd), and makes
  a real show from the files and defaults it played with.
- **One step to a real show:** New Show from Collection, which asks for
  the name with the collection's own name suggested. It makes the show
  with every file in the collection in order, and opens it. This is also
  the first run's nudge into the first show (below).

*From the code:* playing without a saved show means a show that exists
only in memory. The engine reads shows through `ShowSource`
(`spec/layout.md`), and BGTools already builds shows it never saves
(its random modes, `Sources/BGToolsCore`). So there's a precedent.

### Two panels, and what they share (Jason, 2026-09-24)

**The problem it came from, making the first real show:**
1. Jason selected pictures in a collection and chose New Show from them.
2. The show was made at once, with no dialog, using the app's fixed
   defaults: 5-second slides, a dissolve, Pan and Zoom off, fit
   (`ShowDefaults`, `AppModel.newShow`).
3. He then had to work out how to take every slide from 5 to 3.5 seconds,
   and was stuck with the dissolve.

*From the code:* the fix did exist, but nothing pointed to it. The Length
and Transition in Edit Slides' defaults bar change every slide that
doesn't set its own. That's a candidate for a first-encounter tip, and
for G6 in the audit (Edit Show can't reach the defaults at all).

**Two panels, not one (settled, Jason).** Quick Show and New Show… have
too much that differs to be one panel: one plays at once from a pool,
the other makes a show that will be edited. So they're separate panels.
Make Show from Quick Show uses the New Show panel, filled in from the
Quick Show.

**What they share is still worth reading:** the fields both need are the
best guess at what's *essential* to a slideshow. That's what a
newcomer sets, and what Basic most likely shows. It also informs later
thinking (the levels, the first run). The overlap:

| Field | Quick Show (play) | New Show… | Make Show from Quick Show |
|---|---|---|---|
| Name | — | yes (audit H1: nothing Untitled unless OK'd) | yes |
| Pool | Library, a collection, or a show | the selection, or a collection | what the Quick Show played |
| Images only (a show as the pool) | yes | — | — |
| Order: in order or random | yes | yes (random shuffles once, as it's made) | as played |
| Length, transition and its duration | yes | yes: they become the show's defaults | as played |
| Pan and Zoom | yes | yes | as played |
| Audio: a file or a playlist, Loop | yes | yes: goes into the audio row | as played |
| Rhythm | yes | later, in the show | as played |
| Presets | yes | yes, the same presets | — |
| Main button | **Play** (and Send to BGTools) | **Make Show** | **Make Show** |

- **Make Show from Quick Show** (Jason: "a very sweet idea") turns a
  Quick Show you like into a real show you can edit. The player offers
  it, and so does the Quick Show dialog, from its last settings.
- **New Show…** no longer skips straight to a show. From the File menu,
  a collection or a grid selection, it opens the panel. Return accepts
  the pre-filled settings, so it stays one keystroke when the defaults
  are fine.
- **Presets:** the table assumes the two panels share them, so "3.5
  seconds, a quick cut" is set up once. With two panels, that's a choice
  to make, not a given.

**Read across the table, the essentials are:** the pictures (a pool or
a selection), their order, how long each shows, how one gives way to the
next, whether they move (Pan and Zoom), and what plays under them. Six
things. Everything else in the app refines one of them.

**BGTools has the same six** (`Sources/BGToolsCore/DesktopSettings.swift`).
Jason designed it that way before they were counted. Seeing the same six
turn up in three places (Quick Show, New Show, BGTools) confirms them:

| Essential | BGTools today |
|---|---|
| The pictures | a pool: a show, a collection, a random show, or all files (`PlayMode`); **Stills only** narrows it |
| Their order | a show in order, or shuffled; the random modes reshuffle each pass |
| How long each shows | the desktop defaults' length (`randomDefaults`) |
| How one gives way to the next | the desktop defaults' transition |
| Whether they move | the desktop defaults' Pan and Zoom (off by default: it costs CPU) |
| What plays under them | **the weak one.** A **Sound** switch lets a *show's* own audio play. The random modes have no audio of their own |

Two things BGTools adds that are its own, and not essentials of a
slideshow: *where* it plays (each monitor and Space, or All same) and
*when* it pauses (sleep, lock, Low Power, a full-screen app). And one
difference in shape: BGTools' length, transition and movement are one
set shared by every random mode, where Quick Show keeps them per preset.

So **Quick Show and BGTools are nearly the same idea**, one in a window
and one on the desktop. That's why Send to BGTools is mostly a hand-over.
The gaps are audio, and settings per Quick Show rather than one shared
set.

### 3. Levels

Three levels of the same app, from Jason: **Basic**, **Advanced**, and
**"Bring it on!"**.

**Levels hide; they never limit (Jason).** Basic can still play any file
and any show. A level changes what's *shown*, not what the app can do or
what a show holds. So a show built in "Bring it on!" plays exactly the
same in Basic; its lane images and effects simply aren't on view to
edit.

**Where it's chosen (settled, Jason, 2026-09-24):** in the window's
title bar, on the left just after the title, for now. A setting, **Show
level in title bar**, can hide it there. The first-launch welcome says it
can be changed later, and gives its path in the menu bar as well
(View ▸ Level, say), so it's always reachable when it's hidden.

**What each level contains (settled: Jason sets it up by hand).** Jason
arranges the app as he thinks it should be for each level. Claude Code on
his Mac then captures that arrangement as the level's preset:
- *Areas and layout* are already saved settings (`editMode`,
  `inspectorShown`, `frameStripShown`, the columns' widths, and the rest
  in `spec/anatomy.md` §5). They can be read with
  `defaults read com.jhg.showtools`, plus screenshots.
- **This has been done once already.** `DefaultLayout.swift` holds
  Jason's arrangement, "set by hand and captured 2026-09-23": the window
  size (1376 × 835), the Library pane (219), and Edit Show's browser (246) and
  inspector (320). View ▸ Restore Default Layout (⌥⌘0) puts it back, and
  a fresh library opens with it. A level is the same thing, captured
  three times, with more in it: which areas are open, which mode, which
  controls.
- *The Library pane:* `DefaultLayout.restore` doesn't put the Library pane's width
  back, on the belief that doing so caused the layout-loop crash. That
  belief is stale. The crash's confirmed cause was SwiftUI's
  `.inspector()`, and the Library pane was a suspect by coincidence (Jason,
  2026-09-24). Its known bugs are display bugs. So setting the Library pane
  when a level is switched is untested, not ruled out: try it.
- *Controls inside an area* (an inspector section, a menu item, a
  transport toggle) aren't settings today. For those, the capture is a
  written list per level, made from what Jason hides or leaves unused, and
  building the levels means making them hideable.
- *Remember* a test copy shares Jason's preferences domain (CLAUDE.md):
  capture from his real app, as he left it, and don't let a test copy
  write over the keys first.

The table below is the starting guess, until his arrangement replaces
it.

| Level | Meant for | Roughly what shows |
|---|---|---|
| **Basic** | Pictures in order with music, quickly. A little better than the Mac's own slideshow | The library and collections, Play, a simple show view: slides in order, the show's defaults, one audio clip. No timeline pane, no lane, no inspector |
| **Advanced** | Shaping a show slide by slide | Edit Slides with the inspector, transitions, Pan and Zoom, the audio row |
| **"Bring it on!"** | Everything, all the time | Every area and window: Edit Show, the timeline pane and its rows, the lane, markers, Rhythm, the Slide Editor |

**How this fits the rest of the plan:**
- **A level is a preset of which areas show.** `spec/windows.md` makes
  areas that can come and go. A level decides which ones are there to
  begin with, and which inspector sections and menu items show.
  Nothing is lost by switching: a level changes what you see, never what
  the show holds.
- **Levels and the first run** go together: a new user starts in Basic,
  and the first run can offer the next level when it's reached.

## The first run's nudge into a show

**Jason's answer: offer to make it.** After the first import into the
first collection, a dialog adds a little more of the tutorial and asks.
Its wording (Jason, draft):

> Now you've got all the parts needed to start building your own show!
> Ready for the next step?
>
> **[Show Me]**  **[I've Got This]**

- **Show Me** walks through a couple of steps, making the show and
  showing how it was done.
- **I've Got This** leaves them to it, with tooltips and the empty-state
  reminders to go by.

The earlier proposal fits under Show Me:

- **Once My First Collection has files,** its view shows a bar: "Ready
  to make your first show?" with **New Show from “Name”…**. It asks for
  the show's name (suggesting the collection's), then makes the show
  from the collection's files in order.
- **The new show opens,** with its own first-encounter message (what a
  slide is, and how the show's defaults work), and **Play** in the middle
  of it, so the first thing it does is play.
- In Basic, that's the whole path: library, collection, show, playing.
  The levels above offer more, when asked.

## Open questions (for Jason)

Answered 2026-09-24:
- what a level does: it hides, never limits;
- where the level is chosen: the options above;
- what Play does with no show: Quick Show;
- the nudge: Show Me / I've Got This;
- a show as the pool: as built, or Images only;
- keeping a Quick Show: it remembers, plus presets;
- audio: a file or a playlist, with Loop;
- Save as Show: yes, as **Make Show from Quick Show**, through the same
  panel as New Show.

Also answered 2026-09-24: the levels' contents (Jason arranges each
level, and Claude Code captures it), the level picker (the title bar,
with a setting to hide it), and one panel or two (two).

Still open:
1. **Presets across the two panels:** do Quick Show and New Show… share
   one set of presets, or keep their own?
