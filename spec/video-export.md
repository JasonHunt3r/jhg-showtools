# Video export (planned with Jason, 2026-09-22)

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
`outputAspect` (`KenBurnsEditor.swift:8`) is *the main screen's* shape, and
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
- **E4 The panel — NEXT.** File ▸ Export Movie… beside Export Show…: size,
  frame rate, format, where to save, the video-slide note, progress and
  cancel. This is also where the two tracks finally meet: one
  `AVAssetWriter` with both a video and an audio input, the picture loop
  from E2 and the block loop from E3 feeding it. Runs off the main
  thread, reporting through Phase 4's `ExportStatus` / `ExportBanner`.
- **E5 Video slides.** `AVAssetReader` per video slide, pulled forward in
  step with the writer's clock — an `AVAssetImageGenerator` per frame is
  far too slow. Their sound comes through the same `LevelCurve` the live
  player now uses (`spec/video-audio.md`).

## Not in this

Chapter markers, subtitles, a rendered setlist title card, and uploading
anywhere. Animated GIFs export as their frames, as they play.
