# Simple things fast

**Status:** Planned: ideas, not yet designed (Jason, 2026-09-22 and
2026-09-24). Nothing is built. Jason has answered the first round of
questions (below). **Left:** the Quick Show dialog's details, then a
design with Jason.

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

### 3. Levels

Three levels of the same app, from Jason: **Basic**, **Advanced**, and
**"Bring it on!"**.

**Levels hide; they never limit (Jason).** Basic can still play any file
and any show. A level changes what's *shown*, not what the app can do or
what a show holds. So a show built in "Bring it on!" plays exactly the
same in Basic; its lane images and effects simply aren't on view to
edit.

**Where it's chosen (Jason's options):**
- a segmented control on the top bar, like the Edit Slides / Edit Show
  switch; or
- the first-launch welcome, which says it can be changed later and gives
  the path to it in the menu bar (View ▸ Level, say).

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
- audio: a file or a playlist, with Loop.

Still open:
1. **The levels' contents.** Is the split in the table right?
2. **The level picker:** the top bar, the welcome with a menu path, or
   both?
3. **Save as Show…** from a Quick Show: still wanted, now that the dialog
   remembers and has presets? It would turn a good Quick Show into a
   show that can be edited.
