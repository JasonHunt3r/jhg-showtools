# Video export

**Status:** Built 2026-09-22 (E1–E5, the whole plan in one session).
**Left:** a listen — an exported movie against the same show playing,
for timing, crossfades, and a video slide's sound against a song.

The hook has been in since day one (plan, "Video-export hook"): everything
that draws goes through `ShowTimeline.frame(at:)` → `Compositor.compose`,
so an exporter is a new menu item, not a rewrite. `stcli render` already
walks a show's times and writes PNGs through exactly that path — it is the
exporter's inner loop, working today.

## Settled with Jason

| Question | Decision |
|---|---|
| Frame size | **Match the show**, with standard sizes offered too |
| Formats | **H.264/.mp4** (default), **HEVC/.mp4**, **ProRes 422 HQ/.mov** |
| Scope of v1 | **Stills, animations and music.** Video slides second |
| Frame rate | **30 default**, 24 / 30 / 60 in the list |

**Why frame size is a real question.** Shows are not framed 16:9.
`outputAspect` (`PanAndZoomEditor.swift:8`) is *the main screen's* shape, and
`outputPixelSize` is that screen in pixels — it's what the "soft at this
zoom" badge judges against. Jason's shows are composed at roughly 16:10, so
exporting to 1080p would letterbox or crop every slide and shift every Ken
Burns move. The panel therefore defaults to the show's own shape, and a
chosen shape that differs letterboxes rather than cutting the picture.

**Codecs are all the OS's.** Measured with `VTCopyVideoEncoderList` on
Jason's Mac: H.264, HEVC and the whole ProRes family, **all hardware
accelerated** (`AppleProResHW`, the Apple Silicon media engine). Nothing to
bundle, no third-party dependency, no licensing question. Reached through
`AVVideoCodecType` on an `AVAssetWriterInput`.

## The one decision made without asking — CONFIRMED 2026-09-22

**A video slide in a v1 export holds its first frame**, and the panel says
so plainly, naming how many slides are affected. Refusing to export any
show containing video would make the feature useless to Jason, whose test
show opens with a video; silently freezing them without saying so would be
worse. **Jason confirmed this**, choosing it over refusing such shows and
over doing E5 first. `stcli movie` already says the line
("1 video slide holding the first frame"); E4's panel carries it.

Core doesn't decide this: a video slide's picture is whatever the caller's
`source` closure hands back, so E5 changes the caller, not the writer.

## Shape of it

- `MovieExport` lives in `ShowToolsCore` (which already uses AVFoundation
  for `Music`). Like `Compositor.compose`, it takes a closure for media
  rather than reaching for files itself, so Core stays free of the app's
  types and `stcli` can drive it too.
- **One source for levels stays one source.** The offline audio mix uses
  `AudioClip.gain(of:at:among:)` — the same function the live
  `MusicPlayer` uses for volume, fades and equal-power crossfades — so an
  exported mix is by construction what was heard.
- Written off the main thread, reporting through the existing
  `ExportStatus` / `ExportBanner` from Phase 4, with a cancel.

## Steps

- **E1 Settings and codecs — DONE** (`MovieExport.swift`, 15 tests).
  `MovieExportSettings` (size, fps, codec), `MovieCodec` mapping to
  `AVVideoCodecType` and carrying its container, so the ProRes-is-QuickTime
  rule lives in one place rather than in the panel and the writer
  separately. Sizes are forced even on the way in.
  `settings.plan(showAspect:)` settles the framing question above: it
  fits the show's shape inside the asked-for frame and letterboxes,
  never crops. A 16:10 show at 1080p comes out **1728×1080** — it
  pillarboxes, being narrower than 16:9, which is the opposite of what
  the first draft of the test assumed.
- **E2 The picture track — DONE** (`MoviePictureTrack.swift`, 8 tests).
  `AVAssetWriter` with a pixel buffer pool, walking `t` by `1/fps` through
  `frame(at:)` → `Compositor.compose` → `CIContext.render`. Blocking on
  purpose, with `progress` and `isCancelled` closures: **call it off the
  main thread** — E4 does the dispatching. A cancel removes the
  part-written file. `stcli movie <lib> <showID> <WxH> <out> [fps]
  [h264|hevc|prores]` drives it.
  - **Tag the colours, or the picture comes back wrong.** Untagged, the
    encoder wrote YCbCr by one matrix and the reader read it by another:
    green went in at 0.1 and came back at **0.016**, on every codec,
    ProRes included. A `CIColor` rendered straight to a pixel buffer
    round-tripped exactly, which placed the loss in the encode rather
    than the Compositor. Declaring Rec. 709 in `AVVideoColorProperties`
    fixes it, and frames now match to 0.02 on every channel.
  - **Checked by hand**, scratch library: the 11-slide test show exports
    at 1280×800 in 8.1 s (1620 frames, 27 MB), and frame 300 matches
    `stcli render`'s PNG at t=10.0 to a mean of 0.0018 per channel.
- **E3 The sound track — DONE** (`MovieSoundTrack.swift`, 16 tests).
  An offline `AVAudioEngine` (`enableManualRenderingMode`) building the
  same graph as `MusicPlayer` — a player node per song into the main
  mixer, volume from `AudioClip.gain` — set once per 1024-frame block
  (~21 ms, finer than the player's 60 Hz timer). It renders in blocks
  through a `receive` closure, so E4 can append straight to an
  `AVAssetWriter` input; `write()` puts the mix in a file, which is what
  `stcli mix <lib> <showID> <out.caf>` drives. A show with no songs
  renders silence of the right length — the caller decides whether to
  give it a track at all. 48 kHz stereo.
  - **Measure a crossfade as RMS, not peak.** Equal power holds the
    *power* steady, not the peak: two different tones at gain 0.707 each
    sum to a peak of up to 1.41 where their waves align. A peak reading
    makes a correct crossfade look like clipping. The mix really can pass
    full scale mid-crossfade — the live player does exactly the same, one
    `gain` and one graph, so an export is no louder than what was heard.
  - A peak over a window reports its *loudest* moment, not its middle, so
    over a fade out it reads the window's start. Compare it against the
    gain's maximum over the same window.
  - **Checked by hand**, scratch library, with a real AAC click track
    rather than a generated tone: a 20 s song at volume 0.8, 2 s fade in,
    3 s fade out, over the 54 s show. Silent before 5 s and after 25 s,
    and the peak tracks `AudioClip.gain` to a ratio of 0.99–1.00 through
    the flat section. 54 s of mix renders in 0.1 s.
- **E4 The panel — DONE** (`MovieWriter.swift` + `MovieExportPanel.swift`,
  9 tests). Split in two: **E4a** muxes, **E4b** is the UI.
  - **E4a.** One `AVAssetWriter` with a video input and, when the show has
    music, an audio input. `MoviePictureTrack.write` is now this with no
    songs, so one place builds a writer; `MovieSoundRenderer` is E3's mix
    turned inside out, because the muxer can only take audio when the
    writer asks. ProRes carries Linear PCM, the delivery formats AAC.
  - **Two deadlocks, both found by probe.** (1) A track must be marked
    finished the moment its last sample lands: a writer throttles one
    input while another still owes it data, so leaving the picture open
    after its final frame hangs the sound behind it. (2) **Preferring the
    track that is behind is not the same as waiting for it** — an input
    that isn't ready is often waiting on the *other* track before it can
    flush. Spinning on the one behind hung the picture permanently at
    frame 38 of 60 while the sound input sat ready and unasked. Feed
    whichever input will take something; sleep only when neither will.
  - **Interleave the audio by hand.** A non-interleaved ASBD's
    `mBytesPerFrame` counts one channel, so the writer reads a fraction of
    each block. Copying also stops the writer reading a buffer the
    renderer is about to overwrite.
  - **E4b.** File ▸ Export Movie… (⇧⌥⌘E), a Save panel with size on one
    row and rate and format on the next (Jason's layout), over a note that
    speaks only when it has something to say: the letterbox and its inner
    size, video slides holding a first frame, a show with no music.
    Choosing a format renames the file, so ProRes is never left `.mp4`.
    `MovieMedia` loads pictures synchronously — the live `MediaProvider`
    draws nothing until a picture arrives, which is right for a player and
    wrong for an export. Animations use the same `AnimatedFrames.delay`
    the player reads.
  - **Resolve file URLs before leaving the main actor.** Swift 6 caught
    the writing task capturing the SQLite-backed `Library`; it now gets a
    plain `[Int64: URL]`.
  - **Checked by hand**: picking ProRes renames to `.mov`, picking 1080p
    explains the bars ("1660×1080 inside the frame"), and a real export
    writes 54 s at 2940×1912 with an AAC track and a working Cancel.
- **E5 Video slides — DONE** (`MovieVideoFrames.swift`,
  `MovieVideoSound.swift`, `VideoSlideTiming.swift`, 24 tests).
  - **E5a the picture.** An `AVAssetReader` per *slide* (not per file: the
    same video used twice is at two different moments, and a transition
    wants both at once), pulled forward in step with the writer's clock.
    It seeks twice over a slide's life — once at the start, once per loop
    — where an `AVAssetImageGenerator` per frame would seek and decode
    from a keyframe every time.
  - **`VideoSlideTiming` is now the one source for a video slide's
    clock**, asked by both `VideoSlot` and the exporter. It carries a rule
    that is easy to miss when reimplementing it: **a slide held longer
    than the video's remaining length plays it again from `clipStart`**
    rather than freezing, and the line between holding and looping is
    0.1 s (held 4.5 s, a 4 s video loops).
  - **Don't throw away a frame decoded early.** A frame read before its
    moment came was stashed, then overwritten by the next decode, so every
    frame beginning just before the moment asked for was lost and any time
    just past a frame boundary returned the previous frame. Consume what's
    held before decoding more.
  - **E5b the sound.** `AVAudioFile` won't open a video, so the slide's
    audio comes out through an `AVAssetReader` and is laid along the slide
    by `VideoSlideTiming` — so picture and sound loop together, and past
    the end the picture holds its last frame while the sound stops (a held
    frame isn't a held note). The `LevelCurve` is applied per sample and
    baked in, so the node plays at 1: one curve, applied once.
  - **Silent by default is load-bearing.** Only slides whose line has been
    turned up are gathered, so a clip dropped into a show set to music
    never blasts its own audio (`spec/video-audio.md`).
  - **Checked by hand**: against the pre-E5 export, holding changed 10 of
    98 frames over 3.5 s (Pan and Zoom alone) where playing changes 83 of 98.
    For sound, the generated test clip has no audio track at all — rightly
    reported as nothing to mix — so an export was ingested back as a video
    that does have sound: with the line dropped 2.3–5.0 s of an 8 s slide,
    the movie is exactly silent 2.6–4.5 s and sounds either side.

## Still open

- **Nobody has listened to an export yet**, against the same show
  playing. Jason's alpha test (2026-09-22, `077568f`) played an exported
  movie back and nothing broke, so the export works end to end — but that
  was a drive-through, not a listen against the app.
- A very long video slide's sound is decoded whole into memory. Fine for
  slides; worth revisiting if whole films ever become slides.
- `stcli render` still draws video slides as the background colour; only
  `stcli movie` and the app go through `MovieMedia`.

## Not in this

Chapter markers, subtitles, a rendered setlist title card, and uploading
anywhere. Animated GIFs export as their frames, as they play.
