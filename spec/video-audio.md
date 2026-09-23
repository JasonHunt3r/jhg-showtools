# A video slide's own sound (planned with Jason, 2026-09-22)

**Why now.** Video export has to do *something* with a video slide's
audio, and today it does the wrong thing twice over: the sound plays at
full volume with no control, and it comes out of AVPlayer, outside
`MusicPlayer`'s engine, where an offline export can't reach it. Jason's
original idea (plan, "Ask Jason later") was a volume line along the clip,
so part of a clip can be kept — someone speaking — and part dropped, the
dogs barking. That's this.

**Corrected on the way in:** the handoff said a video slide's sound was
"muted for now". It isn't. `MediaProvider.muteVideo` defaults to `false`
and only BGTools sets it true (`BGTools/App/Player.swift:37`), so in
ShowTools video slides play their original audio at 100%, uncontrollably.

## Settled with Jason

| Question | Decision |
|---|---|
| Where the control lives | **Both**: a level line along the video slide in the slides row, and numeric fields in the Slide Inspector |
| Video sound vs music | **Straight mix**, each at its own level. No automatic ducking — the two level lines are the control |
| A new video slide defaults to | **Silent.** Dropping a clip into a show set to music must never suddenly blast its original audio |
| How much control along the clip | **Multiple points** — a real automation curve, not one level plus fades |

Nothing to preserve: Jason hasn't built a real show yet, so defaulting
existing video slides to silent costs nothing. Check this still holds
before building.

## The model

A new `LevelCurve` in `ShowToolsCore` (`Levels.swift`), decoded field by
field like every saved type, with a lenient point list so one unreadable
point doesn't cost the rest:

```swift
public struct LevelPoint {   // time is clip-relative seconds
    var time: Double
    var level: Double        // 0…1
}
public struct LevelCurve {
    var points: [LevelPoint]
    func level(at local: Double) -> Double   // linear between points,
}                                            // clamped outside the ends
```

Two things make this cheap:

- **No schema migration.** A slide's settings are JSON in the `slides`
  table, decoded field by field, so `audio` is a new optional field on
  `Slide` and old rows simply don't have it. Library schema stays 12.
- **The existing clips keep their model.** A song's `volume`/`fadeIn`/
  `fadeOut` are *not* migrated to points. `AudioClip` gains a computed
  `curve` (a four-point curve: 0 → volume → volume → 0) so `LevelLine`
  has one thing to draw, while the saved fields stay exactly as they are.
  That honours the settings-JSON rule and leaves the door open to giving
  songs and lane images real curves later, without a data change now.

Absent or empty `audio` on a video slide means **silent**, which is the
default. A still slide has no `audio` field at all.

## Playing it, and the fork worth knowing about

The *envelope* — what level at time t — lives in Core and has exactly one
implementation. How it's **applied** differs by player, and deliberately:

- **Live:** set `AVPlayer.volume` from the curve, stepped on a timer, the
  way `MusicPlayer.applyLevels` already does for songs. AVPlayer keeps
  its own picture and sound together, which is worth not disturbing.
- **Export:** AVPlayer can't be captured offline, so the video's audio
  track is pulled with `AVAssetReader` into the offline engine and the
  same curve is applied there.

This mirrors the picture, which already has two paths (AVPlayer live, the
Compositor for `stcli render` and export). The single-source rule is kept
where it matters: one curve, one `level(at:)`, two players.

`MediaProvider.muteVideo` stays as it is — BGTools still mutes the lot.

## Steps

**V1–V5 BUILT 2026-09-22.** V6 (listening) needs Jason's ears.

- **V1 `LevelCurve` in Core**, with tests: `level(at:)` between, on and
  outside points; field-by-field decode; a lenient point list.
- **V2 The slide's field.** `audio` on `Slide`, silent by default for
  video, edited through a `ShowMutator` with an undo name. Tests that a
  show without the field reads back silent and a round trip keeps points.
- **V3 The level line, points mode.** `LevelLine` currently takes
  `level`/`fadeIn`/`fadeOut` and is used twice (`MusicRow`, `ImagesRow`).
  It gains a curve mode: click the line to add a point, drag one to move
  it, ⌥-click or Delete to remove. Commits once on release, one undo
  step, like every other drag. **Look up how Final Cut and Logic handle
  add/remove on an automation line before building the gestures** — same
  rule as the folder tabs.
- **V4 The inspector.** Numeric fields for the selected video slide,
  mirroring the line.
- **V5 Live playback.** Apply the curve to `AVPlayer.volume`.
- **V6 Check it.** Tests, then by hand: a clip whose middle is dropped,
  against a song, exported later in E-steps.

Only then video export, which now has a defined audio source.

## Not in this

Giving songs and lane images real curves (the computed `curve` leaves
room, but their saved model doesn't change), automatic ducking, and the
video's audio in the lane.

## As built (V1–V3, 2026-09-22)

`Sources/ShowToolsCore/Levels.swift` and `Sources/ShowToolsApp/CurveLine.swift`.
`SlideSettings.audio` is nil when silent, so a slide turned back down leaves
no field behind. Library schema stayed **12**: no migration. 18 tests
(193 core in total).

**The gestures, from Apple's own apps** — the two split the job between
them, so the answer came from both:

- **⌥-click the line adds a point**, at the level the line already has
  there, so clicking never moves it (Final Cut: *"Option-click … at a point
  on the horizontal effect control where you want to add a keyframe"*).
- **Drag a point** to move it in time and level at once (Logic).
- **Double-click a point removes it** (Logic). Apple's Final Cut pages
  never say how to delete a keyframe, so Logic's gesture was taken rather
  than guessing.
- **Drag the line** moves every point together, stopping when the highest
  or lowest lands; on a **silent clip it sets one flat level**, so turning
  a clip up stays a single drag (Jason, so the simple case stays simple).
- The double-click is read from `NSApp.currentEvent?.clickCount`, not an
  `onTapGesture(count: 2)`, which would hold every single click back while
  it waited for a second — the same reason the storyline's blocks do it
  that way.

**Checked by hand**, with axtool on the scratch library, reading the saved
JSON back out of the database after each edit: drag up → a flat 0.6 curve
across the clip; ⌥-click → a third point at 1.8s, level unchanged;
double-click → gone again; ⌘Z steps back one edit at a time and three
undos return the slide to `{}`. A dip built by hand (0.6 → 0 from 1.3s to
2.6s → 0.6) draws as it should.

**A drawing bug worth remembering.** The line rendered from the first
build, exactly where the geometry said — and was invisible. A video
block is a strip of the film itself, and the line was orange at 35% over
an orange frame. Eyeballing the screenshot said "not drawing"; sampling
the pixel rows said "drawing, at y=58 of 64, contrast 19/13/-6". The fix
is a dark outline stroked under the line, as the app already does with a
shadow behind the soft badge. **Measure before concluding a view isn't
rendering.**

### Left for Jason's eye

- The outermost points sit at the block's very edges, so their diamonds
  are half-clipped by the rounded corners. Normal enough for an
  automation line, but it may want insetting.
- The undo *names* ("Add Volume Point" and so on) weren't confirmed in the
  Edit menu — only that undo and redo step correctly, one step per edit.

## V4 and V5, as built (2026-09-22)

**V4, the inspector** (`SlideInspector.soundSection`). A **Sound** section,
shown only for a video slide, and only for the first selected one — the
points belong to one clip, as the Effects timeline already says of itself.
It shows the line's two states rather than a second editor for it:

- **flat or silent:** one `Volume` slider (the existing `CommitSlider`, so
  it has a numeric field and commits once). Turning it down to nothing
  clears `audio` altogether, so the slide goes back to having no field at
  all rather than carrying a flat zero — the same end state three undos
  reach on the timeline.
- **shaped:** a row per point, time in seconds and level in percent, each
  a number you can type, with a remove button, and an Add Point button.

There is deliberately no single volume control while a curve is shaped:
it would either flatten the shape or need a meaning ("move it all"?) that
the line itself already expresses better by dragging.

**V5, live playback.** `ResolvedSlide` gained `audio`, filled from the
slide's settings for video and left empty for everything else, so the
curve reaches the player with the rest of the resolved slide.
`MediaProvider.image(for:playing:)` sets `slot.volume` from
`audio.level(at: layer.localTime)` each frame, and a newly made `VideoSlot`
opens at `level(at: 0)` rather than full volume — otherwise a frame's worth
of original audio is heard before the first update. `VideoSlot.volume` is
`AVPlayer.volume`, separate from `muted`, which BGTools still uses to
silence everything.

Two more tests (195 core): a video slide's curve reaches the resolved
slide, and a video slide without one resolves silent while a still never
carries a curve at all.

### V6 is Jason's

The numbers are checked; the sound isn't. What needs ears: a clip whose
middle is dropped, a video against a song (they should simply mix, no
ducking), and whether the level changes smoothly or steps audibly — the
volume is set once per drawn frame, which should be inaudible but hasn't
been heard.
