import Foundation

/// Which moment of a video file a video slide is showing.
///
/// **One source for a video slide's clock.** The live player (`VideoSlot`)
/// and the exporter both ask this, so an exported video slide shows the
/// same frame the player would at that moment — including the looping
/// rule, which is easy to miss: a slide held longer than the video's
/// remaining length plays it again from `clipStart` rather than freezing
/// on the last frame.
public enum VideoSlideTiming {

    /// Where in the file to be, and whether the slide has run past its
    /// video and is holding still.
    ///
    /// - Parameters:
    ///   - localTime: seconds since the slide's start.
    ///   - slideLength: how long the slide is held.
    ///   - clipStart: seconds into the file the slide begins at.
    ///   - duration: the file's own length.
    public static func position(localTime: Double, slideLength: Double,
                                clipStart: Double, duration: Double)
    -> (time: Double, holding: Bool, loops: Bool) {
        // A frame's worth of slack at the end: asking for the very last
        // instant of a file often lands past its final sample.
        let lastFrame = max(duration - 0.04, 0)
        let span = max(duration - clipStart, 0.04)
        let loops = slideLength > span + 0.1
        let time = duration <= 0 ? localTime
            : loops && localTime < slideLength ? clipStart + localTime.truncatingRemainder(dividingBy: span)
            : min(clipStart + localTime, lastFrame)
        let holding = localTime >= (loops ? slideLength : span - 0.04)
        return (time, holding, loops)
    }
}
