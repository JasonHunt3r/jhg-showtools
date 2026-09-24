# How we design ShowTools, and why

**Kernel.** Started 2026-09-24, from one evening's planning. It's meant
to grow, with hindsight, into a design manual: the principles behind the
app, each with the moment it was learned. It's not a rulebook (CLAUDE.md
has the rules) and not a plan (`spec/plan.md` has the decisions). It
answers *why things are the way they are*, so the next decision can be
made the same way.

Each principle has a story: what we did, what showed it was wrong or
right, and what changed.

## The six pillars of a slideshow

A slideshow is six things:

1. **The pictures:** which ones.
2. **Their order.**
3. **How long each shows.**
4. **How one gives way to the next:** the transition.
5. **Whether they move:** Pan and Zoom.
6. **What plays under them:** audio.

Everything else in ShowTools refines one of these six: transforms,
rotation, the lane, effects, markers, rhythm, levels of sound.

**How we know.** Jason designed the app around them before anyone
counted. They were counted on 2026-09-24, while working out what a
Quick Show dialog needs and what a New Show… dialog needs. The fields the
two shared were these six. Then BGTools, designed separately for the
desktop, turned out to have the same six in its settings. Three places,
one set: that's the evidence.

## Perceptual efficiency

**Wherever someone starts, the six come first, and nothing gets ahead of
them.** Refinements wait until they're asked for.

- *The story:* making the first real show (2026-09-24). The app can do
  a lot, but getting from a folder of photos to a playing slideshow was
  slow. With every area open, it was a lot to take in. The depth wasn't
  wrong. It was just in front.
- *What follows:* Quick Show (a slideshow in seconds), levels (Basic,
  Advanced, "Bring it on!"), and a first run that teaches one step at a
  time (`spec/simple-things-fast.md`).
- *The test for anything new:* which of the six does it serve, and does
  it put anything ahead of them?

## Hide, never limit

A simpler view shows less. It never does less. Basic can play any show,
however it was built. A level changes what's on view, never what a show
holds or what the app can do.

## Two things that are one, and one thing that's two

Look for the same idea wearing two names, and for two ideas sharing one.

- **Two that are nearly one:** Quick Show and BGTools. Both play a pool
  of pictures with a length, a transition and movement. One plays in a
  window, one on the desktop. Seeing that made "Send to BGTools" a
  hand-over, not a new feature.
- **One that had to be two:** a single panel for Quick Show and New
  Show… looked tidy. But one plays at once and the other makes something
  to edit, and too much differed, so they're two panels. The overlap
  still taught something: it's where the six pillars were found.
- **One show, two views:** Edit Slides and Edit Show are two views of one
  show, each built for its own job (a list for order and settings, a
  timeline for time). They needn't offer the same tools. But **where both
  offer the same action, it gives the same result.** Undoing an added
  slide worked in one and not the other; a drop inserted in one and
  appended in the other. Different tools is design; the same tool acting
  differently is a bug (`spec/hig-audit.md` §G).

## Names describe; they don't refer

A name says what a thing does, in words a newcomer already has.

- **Ken Burns → Pan and Zoom** (2026-09-22): the old name was a
  reference you had to know. The new one says what happens.
- **Song → audio clip** (2026-09-24): a recording of the wind, a
  jackhammer, or a voice isn't a song. The name has to hold everything
  it might be.
- **Edit zone → timeline pane** (2026-09-24): where a word is standard
  across the field (Final Cut, Premiere and Resolve all say "timeline"),
  use it.
- **"A simple way in" → "simple things fast"** (2026-09-24): the old
  phrase didn't say what was wrong. The new one does.
- One name per thing: `spec/anatomy.md`.

## A button means what it says

- **Cancel means never mind** (2026-09-24). New Collection used to make
  "Untitled Collection" at once. Now the name comes first, and nothing is
  made until OK. Nothing is ever Untitled unless someone clicked OK on
  that name.
- **Every edit is one undo step, and every one can be undone.** Three
  ways of adding slides weren't recorded for undo, so ⌘Z skipped them
  (found 2026-09-24, audit G1). The fix also took away the default that
  let it happen, so the next caller can't leave it out.

## An empty place says why it's empty

The way forward depends on *why* it's empty:
- **A container you're meant to fill** (the library, a collection, a
  show): it says what it's for, and has the button that fills it. The
  first time, it welcomes and teaches; after that, it's a short reminder
  with the same button. The story: a new collection gave no hint of how
  to fill it, short of hunting for a small Import button or dragging onto
  a small sidebar row.
- **Hidden by a search or filter:** say so, and offer to clear it.
- **Waiting for a selection** (the inspector): say what to select.
- **A row waiting for a drop:** a quiet hint, no button.

(Audit H2; `spec/first-run-brief.md`.)

## Behaviour follows the job

A window follows the show on screen if its job is the show: the timeline,
the viewer. It stays put if its job is a source: the library. Where the
two need joining, the user asks, for example with Show in Library. A
panel floats if it serves what's in front (the library over a new
collection, the inspector). An ordinary window can go behind (the
Timeline window). (`spec/windows.md`.)

## Settings belong to each use

A file carries no slide settings. Each slide, one *use* of a file, has
its own. The same photo can be three slides, three ways. (Settled
2026-09-20, `spec/plan.md`.)

## Two kinds of expected behaviour

- **The obvious ones:** what every Mac app does. ⌘A selects all, Delete
  deletes, right-click offers what's under the pointer, arrow keys move
  the selection, Space opens Quick Look. They can be listed ahead of
  time, and are: `spec/hig-audit.md`.
- **The contextual ones:** what *this* app should do, which only shows up
  when it's used for real. Nothing lists them in advance. Jason finds
  them by making shows: New Show should ask for the length before making
  twenty 5-second slides; a new collection should say how to fill it.
  They're recorded as they're found, with the story, here and in the
  audit.

## The person using it sees what the logs don't

The layout-loop crash (2026-09-23) took three sessions, including an
all-night one. Claude kept building confident theories from exception
logs and timestamps, and kept forcing the square peg. Each time, the way
forward came from Jason's own account of what he'd done and seen: his
memory of the sessions contradicted a log-based timeline, and his
questions pushed the digging somewhere new.
(`spec/history/2026-09-23-crash-hunt-session3.md` names the failures.)

**The eureka, in Jason's words (2026-09-24):** Claude "kept trying to
rewrite the code to make the conflicting wrappers work". Jason asked:
*tell me the cascade that leads to this.* The answer was that
`.inspector()` couldn't sit inside the container it was in. And Jason
said: then **don't wrap it in that**. "Why do they work fine over here
for two days, but don't work in your later stuff?" Edit Show's inspector
had worked for days on a hand-rolled split (`ColumnsSplitView`). Edit
Slides' inspector used SwiftUI's `.inspector()`, and that was the one
crashing. The fix was to use what already worked
(`spec/edit-slides-inspector-port.md`).

**The lessons:**
- **When the person who uses the app every day says something doesn't
  match their experience,** that's better evidence than a reading of the
  logs. Ask what they remember before building another theory.
- **Ask for the cascade, not another patch.** Trace what leads to the
  failure, step by step, before changing code. Forcing a fix onto a cause
  you haven't traced is the square peg.
- **When one thing works and its twin doesn't, the difference is the
  answer.** Compare with the working sibling before inventing anything.

**More from the debrief** (`spec/history/2026-09-24-crash-hunt-debrief.md`):
- **A latent bug isn't in the latest change.** The inspector was never
  crash-tested when it went in, and it surfaced many steps later. The
  hunt went backwards through the newest work (the rename, HEAD, even
  "clicking too fast") and found nothing. Ask what was never tested, not
  what changed last.
- **A repro is not a cause.** Rapid mode-switching triggered the crash
  quickly. It never caused it.
- **Knowing you don't understand is a finding.** When fixes keep failing,
  say what isn't understood and look upstream, before the next rewrite.
- **Conjecture isn't a vector.** A guess that gets built on becomes a
  direction nobody chose.

## Volunteered work follows the house pattern

**The story:** the feature at the heart of the crash, Edit Slides'
inspector, was design Claude volunteered. Jason was surprised to find it
had been built at all. It was a good idea. But it didn't use the
established convention: Edit Show's collection list (the browser) sat
right next to an inspector pane on `ColumnsSplitView`, and that worked.
The new one used a different mechanism, SwiftUI's `.inspector()`, and
that difference was the crash.

**The principles:**
- **Something almost identical to what exists uses the same mechanism.**
  A second inspector, list or panel starts as a copy of the first one's
  pattern. A new mechanism needs a reason, stated.
- **Volunteered work is said out loud.** An idea built without being
  asked for is announced as such, in the commit and in the reply, so
  it's never discovered by surprise.

## Know before you build

- **Measure, don't guess.** It's a CLAUDE.md rule, because guesses in
  this codebase have been wrong in convincing ways.
- **Stale knowledge is a guess too.** On 2026-09-24 an old code comment
  said setting the sidebar caused the layout-loop crash. It was written
  before the real cause (SwiftUI's `.inspector()`) was found, and it was
  repeated as fact until Jason caught it. Caught early, it cost one
  paragraph. Caught late, it could have steered a long build. Check a
  belief's date against what's been learned since.
