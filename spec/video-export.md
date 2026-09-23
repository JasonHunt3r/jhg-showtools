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

## The one decision made without asking

**A video slide in a v1 export holds its first frame**, and the panel says
so plainly, naming how many slides are affected. Refusing to export any
show containing video would make the feature useless to Jason, whose test
show opens with a video; silently freezing them without saying so would be
worse. **Confirm this.**

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

- **E1 Settings and codecs.** `MovieExportSettings` (size, fps, codec) and
  a `Codec` enum mapping to `AVVideoCodecType` and a file extension.
  Tests: the mapping, the container rule (ProRes is `.mov`, never `.mp4`),
  and that sizes come out even, which encoders require.
- **E2 The picture track.** `AVAssetWriter` with a pixel buffer pool; walk
  `t` from 0 to the show's duration by `1/fps`, `timeline.frame(at:)` →
  `Compositor.compose` → `CIContext.render` into the buffer. Test by
  writing a short show and reading it back with `AVAssetReader`: frame
  count, frame size, and a frame's colour matching what `Compositor` draws
  at that time — the same by-eye check `stcli render` does, automated.
- **E3 The sound track.** An offline `AVAudioEngine`
  (`enableManualRenderingMode`), the same node-per-clip graph as
  `MusicPlayer`, levels from `AudioClip.gain`. Test: a show with a song
  reads back with the right number of samples, and a stretch the level
  line silences is silent.
- **E4 The panel.** File ▸ Export Movie… beside Export Show…: size, frame
  rate, format, where to save, the video-slide note, progress and cancel.
- **E5 Video slides.** `AVAssetReader` per video slide, pulled forward in
  step with the writer's clock — an `AVAssetImageGenerator` per frame is
  far too slow. Their sound comes through the same `LevelCurve` the live
  player now uses (`spec/video-audio.md`).

## Not in this

Chapter markers, subtitles, a rendered setlist title card, and uploading
anywhere. Animated GIFs export as their frames, as they play.
