# Simple things fast

**Status:** Planned: ideas, not yet designed (Jason, 2026-09-22 and
2026-09-24). Nothing is built. **Left:** a design with Jason, starting
from the open questions.

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

## Three answers, which work together

### 1. A guided first run

Each first encounter teaches itself and nudges to the next step. It
already has its own brief, `spec/first-run-brief.md`, where Jason's
draft wording from 2026-09-24 now lives. The sequence is:

1. The empty library welcomes you.
2. You add files.
3. **My First Collection**: name it and fill it.
4. A nudge into the first show.

### 2. Play without building

A slideshow should be able to start from what's already there, with no
show made first:

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

This is the step Jason didn't have an idea for yet. A proposal:

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

1. **The levels' names and contents.** Is the split above right? Is the
   level chosen per library, or for the app as a whole? Where does it
   live: a toolbar control, the View menu, or Settings?
2. **A show that uses more than its level shows.** For example, a show
   built in "Bring it on!" with lane images, opened in Basic. Does Basic
   show a note ("this show uses Advanced settings"), switch up itself, or
   simply play it as it is?
3. **Play without building:** what the player plays when nothing is
   selected in the grid (everything in view?), and whether Save as
   Show… belongs in the player, or on the grid afterwards.
4. **The nudge into a show:** is the bar and New Show from “Name”… the
   right step, or should the first show make itself?
