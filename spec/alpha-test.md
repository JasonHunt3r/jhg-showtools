# Alpha test drive (2026-09-22)

Everything planned is built — Phases 1–5 and video export. This is the
crash-test pass: use it properly, break it, and write down everything that
is wrong, ugly, or surprising. **Notes are the deliverable.** Nothing here
needs Claude; it's all self-service.

There is a notes template at the bottom. Keep it open while you go.

---

## Setting up

**The app** is installed at `~/Applications/ShowTools.app`. Open it the
normal way. It opens your **real library** (`~/Pictures/ShowTools
Library.noindex`), which is what you want for a crash test.

**The demo show is already in your library.** Open the app and **Shorty**
is in the sidebar — 5 slides, 24 seconds. Nothing to set up.

A **reference export** of it, rendered by the exporter, sits at
`~/ShowTools Demo/Shorty (reference export).mp4`. Play that against the
app to compare.

If you ever want it back, or want it fresh:

```sh
cd ~/Projects/ShowTools
tools/add-demo-show.sh          # adds/replaces Shorty in your library (app quit)
tools/make-demo-show.sh         # rebuilds the separate demo library too
```

Shorty's media (8 files) is the only thing in your library, so deleting
the show and its files puts you back to empty.

---

## Shorty, second by second

It is built so each thing happens **on its own**, with nothing else going
on to confuse it. A click track runs on every beat (120 BPM, one every
half-second), so timing is checkable by ear.

| Time | What it is | What to check |
|---|---|---|
| 0–4s | A still with **Ken Burns**, over song A | Does the move look smooth, or does it step? |
| **4s** | A **hard cut** to the next still | Does it land *exactly* on a beat, or a frame late? |
| 4.5–7.5s | A **lane image** fades over the top | Does it sit where you'd expect? |
| 8–12s | An **animated GIF**, reached by a 1s dissolve | Does the animation run at the right speed? |
| **12–14s** | The two songs **crossfade** | Low clicks become high clicks. Does the loudness *hold* through the middle, or sag? |
| 14–24s | A **video slide**, playing its own frames | Is the picture moving, or frozen on one frame? |
| 17–20s | The video's **own sound is dropped to silence**, mid-clip | The warbling tone should vanish while the music carries straight on — then come back at ~20.4s |

That last one is the headline. The video has a warbling tone quite unlike
the clicks, so when its level line drops you should hear exactly one of
the two sounds disappear.

---

## The main event: play it, then export it, then compare

1. **Play Shorty in the app.** Watch and listen against the table above.
2. **File ▸ Export Movie…** (⇧⌥⌘E). Leave the settings alone the first
   time. Save it to the Desktop.
3. **Open the movie in QuickTime and play it.**
4. **Compare the two.** This is the bit no one has done yet.

What I'd most like your ears on:

- **Does the export sound like the app?** Every level in it is measured
  against the same functions the player uses, but no one has heard them
  side by side.
- **The video slide's sound level** is set *once per drawn frame* live,
  and *per sample* in the export. So the export may be the smoother of
  the two. If the live one steps or zippers where the export glides,
  that's a real finding and worth writing down.
- **The crossfade.** Measured, it sags about 1.3 dB in the middle where
  it should hold flat. That may be nothing, or it may be audible. Your
  ears decide.
- **Sync.** Do the cut at 4s and the picture changes land with the beat in
  both?

Then try the settings: export at **1080p** (the note should tell you it
will letterbox and by how much — nothing should be cut off), at **24 and
60 fps**, and as **ProRes** (the filename must change to `.mov`). And
press **Cancel** partway through a big one: it should stop and leave no
half-written file behind.

---

## Then break it

Things that have never been done by a person. Rough treatment is the
point.

**The export panel**
- Export while a show is playing. Export twice in a row. Export a show
  with no music, and a show with a single slide.
- Save over a file that already exists. Save into a folder you can't
  write to.

**Your own library, for real**
- Make a real show, end to end, from importing pictures to exporting it.
  This is the first time that has ever been done.
- Drag files in from Finder and from Photos (never tested by hand).
- ⌘Z everywhere, especially after a drag, and with the Info panel focused.

**The bits that have never had a person's hands on them**
- **Touch ID** on a private library.
- **A second screen**, and BGTools' desktop mode on it.
- **Bluetooth headphones** — the output latency is compensated but
  untested, so sync may drift.
- **Dragging a song in** from Finder or Music.
- The **Rhythm panel**: its look, and Listen by ear against real music.

**Known already — no need to report unless worse than described**
- The inspector's "Style" label wraps one letter per line when Transition
  in is Custom.
- The Edit Slides header bar overflows at normal window widths.
- A song lying wholly inside another plays over it without crossfading.
- Video can't go in the lane; the frame strip shows only a video's first
  frame; the onion skin skips video slides.
- Inspector sliders update on release, not while dragging.
- CPU is 33–37% while playing.

---

## Notes template

Copy this per finding. Small and specific beats long and general.

```
WHAT I DID:
WHAT I EXPECTED:
WHAT HAPPENED:
WHERE:            (show, slide, panel, time in the show)
HOW BAD:          crash / wrong / ugly / just noting it
```

Crashes are the most valuable thing you can catch, so if one happens,
note what you did in the ten seconds before it — that's usually enough to
find it.
