import Foundation
import AVFoundation
import CoreImage
import CoreVideo

// Video export (plan, `spec/video-export.md`). E4a: the two tracks meet.
//
// One `AVAssetWriter` with a video input and, when the show has music, an
// audio input. The picture loop is E2's and the sound loop is E3's; what
// is new here is feeding both in step. A writer wants its tracks
// interleaved by time, so each turn of the loop hands the next sample to
// whichever track is furthest behind on the show's clock and ready for it.
//
// `MoviePictureTrack.write` is this with no songs, so there is one place
// that builds a writer rather than two that can drift apart.

public enum MovieExport {

    /// Writes a show as a movie: picture, and sound if it has any.
    ///
    /// **Call this off the main thread.** It blocks, waiting on the
    /// encoder; `progress` and `isCancelled` are called on this thread, and
    /// a cancel removes the part-written file.
    ///
    /// A video slide's picture is whatever `source` hands back, and its own
    /// sound comes in through `videoSound` (E5).
    @discardableResult
    public static func write(timeline: ShowTimeline,
                             songs: [MovieSong] = [],
                             videoSound: [MovieVideoSound] = [],
                             to url: URL,
                             settings: MovieExportSettings,
                             showAspect: CGFloat,
                             context: CIContext = CIContext(),
                             overlaySource: ((OverlayLayer) -> CIImage?)? = nil,
                             progress: ((Double) -> Void)? = nil,
                             isCancelled: (() -> Bool)? = nil,
                             source: (Layer) -> CIImage?) throws -> MovieExportResult {

        let fps = settings.frameRate.fps
        let totalFrames = MoviePictureTrack.frameCount(duration: timeline.duration, fps: fps)
        guard totalFrames > 0 else { throw MovieExportError.emptyShow }

        let plan = settings.plan(showAspect: showAspect)
        let canvas = CGRect(origin: .zero, size: plan.canvas)

        // The mix, if there is one. Built before the writer so a bad song
        // fails before a file is made.
        var sound: MovieSoundRenderer?
        if !songs.isEmpty || !videoSound.isEmpty {
            let renderer = try MovieSoundRenderer(songs: songs, videos: videoSound,
                                                  duration: timeline.duration)
            // A show whose sound has all gone gets no track, rather than a
            // silent one nobody asked for.
            if renderer.result.songsMixed > 0 || renderer.result.videoSlidesMixed > 0 {
                sound = renderer
            }
        }

        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: settings.codec.container.fileType)

        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: settings.codec.avCodec,
            AVVideoWidthKey: Int(plan.canvas.width),
            AVVideoHeightKey: Int(plan.canvas.height),
            // Say what the colours are. Untagged, an encoder writes YCbCr by
            // one matrix and a player reads it by another: measured as a
            // green channel coming back at 0.016 where 0.1 went in, on every
            // codec including ProRes. Frames are rendered sRGB, and Rec. 709
            // is the tag every player reads that way.
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        video.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: video,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(plan.canvas.width),
                kCVPixelBufferHeightKey as String: Int(plan.canvas.height),
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ])
        guard writer.canAdd(video) else {
            throw MovieExportError.writerFailed("the writer wouldn't take a \(settings.codec.name) track")
        }
        writer.add(video)

        var audio: AVAssetWriterInput?
        if let sound {
            let input = AVAssetWriterInput(mediaType: .audio,
                                           outputSettings: settings.codec.audioSettings(sampleRate: sound.format.sampleRate,
                                                                                        channels: sound.format.channelCount))
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else {
                throw MovieExportError.writerFailed("the writer wouldn't take a sound track")
            }
            writer.add(input)
            audio = input
        }

        guard writer.startWriting() else {
            throw MovieExportError.writerFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }
        writer.startSession(atSourceTime: .zero)

        func fail(_ e: MovieExportError) -> MovieExportError {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            return e
        }

        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let black = CIImage(color: .black).cropped(to: canvas)
        let offset = CGAffineTransform(translationX: plan.picture.minX, y: plan.picture.minY)

        var frame = 0
        var soundDone = (sound == nil)
        var videoDone = false
        var soundFrames: AVAudioFramePosition = 0

        // Each track is marked finished the moment its last sample lands,
        // not after the loop. A writer throttles one input while another
        // still owes it data for the same stretch of time, so leaving the
        // picture open after its last frame deadlocks the sound behind it —
        // measured as a hang, 2026-09-22.
        func finishVideo() {
            guard !videoDone else { return }
            videoDone = true
            video.markAsFinished()
        }

        while !videoDone || !soundDone {
            if isCancelled?() == true { throw fail(.cancelled) }
            if writer.status == .failed {
                throw fail(.writerFailed(writer.error?.localizedDescription ?? "the encoder failed"))
            }

            // Whichever track is furthest behind gets the next sample, so the
            // file comes out interleaved rather than one whole track then the
            // other (which would hold the entire mix in memory).
            //
            // **Preferring a track is not the same as waiting for it.** An
            // input that isn't ready is often waiting on the *other* track
            // to catch up before it can flush, so spinning on the one that
            // is behind deadlocks: measured as the picture going
            // permanently unready at frame 38 of 60 while the sound input
            // sat ready and unasked. Feed whichever input will take
            // something, and only sleep when neither will.
            let videoTime = videoDone ? .infinity : Double(frame) / Double(fps)
            let audioTime = soundDone ? .infinity : Double(soundFrames) / (sound?.format.sampleRate ?? 1)
            let videoReady = !videoDone && video.isReadyForMoreMediaData
            let audioReady = !soundDone && (audio?.isReadyForMoreMediaData ?? false)

            guard videoReady || audioReady else { Thread.sleep(forTimeInterval: 0.002); continue }
            // Take the one behind when it will take data; otherwise the other.
            let takeAudio = audioReady && (!videoReady || audioTime <= videoTime)

            if takeAudio, let sound, let audio {
                if let block = try sound.next() {
                    guard let sample = sampleBuffer(from: block.buffer, at: block.frame,
                                                    rate: sound.format.sampleRate) else {
                        throw fail(.writerFailed("a block of sound wouldn't convert"))
                    }
                    guard audio.append(sample) else {
                        throw fail(.writerFailed(writer.error?.localizedDescription ?? "a block of sound wouldn't append"))
                    }
                    soundFrames = sound.framesRendered
                } else {
                    audio.markAsFinished()
                    soundDone = true
                }
                continue
            }

            let t = Double(frame) / Double(fps)
            var picture = Compositor.compose(timeline.frame(at: t), size: plan.picture.size,
                                             overlay: timeline.overlay(at: t),
                                             overlaySource: overlaySource, source: source)
            if plan.isLetterboxed {
                picture = picture.transformed(by: offset).composited(over: black)
            }

            guard let pool = adaptor.pixelBufferPool else { throw fail(.noPixelBuffer) }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                  let buffer else { throw fail(.noPixelBuffer) }

            context.render(picture.cropped(to: canvas), to: buffer, bounds: canvas, colorSpace: srgb)

            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw fail(.writerFailed(writer.error?.localizedDescription ?? "a frame wouldn't append"))
            }
            frame += 1
            progress?(Double(frame) / Double(totalFrames))
            if frame >= totalFrames { finishVideo() }
        }

        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        if writer.status != .completed {
            try? FileManager.default.removeItem(at: url)
            throw MovieExportError.writerFailed(writer.error?.localizedDescription ?? "the file wouldn't finish")
        }
        return MovieExportResult(url: url, size: plan.canvas, frameCount: totalFrames, frameRate: fps,
                                 soundFrames: soundFrames, songsMixed: sound?.result.songsMixed ?? 0,
                                 videoSlidesMixed: sound?.result.videoSlidesMixed ?? 0)
    }

    /// A block of the mix as something a writer input will take.
    ///
    /// The engine renders **non-interleaved** float, and handing that
    /// straight over doesn't work: a non-interleaved ASBD's `mBytesPerFrame`
    /// counts one channel, so the writer reads a fraction of each block,
    /// never sees the sound track advance, and throttles the picture until
    /// it stops asking for frames altogether. Measured as a hang at frame
    /// 38 of 60 with the audio input still reporting ready, 2026-09-22.
    ///
    /// So the samples are interleaved into a block buffer here, described by
    /// a packed ASBD. Copying also removes a second hazard: the renderer
    /// hands back the same buffer every block, which the writer would
    /// otherwise still be reading when the next block overwrote it.
    static func sampleBuffer(from pcm: AVAudioPCMBuffer, at frame: AVAudioFramePosition,
                             rate: Double) -> CMSampleBuffer? {
        let frames = Int(pcm.frameLength)
        let channels = Int(pcm.format.channelCount)
        guard frames > 0, channels > 0, let source = pcm.floatChannelData else { return nil }

        var asbd = AudioStreamBasicDescription(
            mSampleRate: rate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(4 * channels),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32,
            mReserved: 0)
        var formatDescription: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd,
                                             layoutSize: 0, layout: nil, magicCookieSize: 0,
                                             magicCookie: nil, extensions: nil,
                                             formatDescriptionOut: &formatDescription) == noErr,
              let formatDescription else { return nil }

        let bytes = frames * channels * 4
        guard let data = malloc(bytes) else { return nil }
        let interleaved = data.bindMemory(to: Float.self, capacity: frames * channels)
        for c in 0..<channels {
            let channel = source[c]
            for i in 0..<frames { interleaved[i * channels + c] = channel[i] }
        }

        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: data, blockLength: bytes,
            blockAllocator: kCFAllocatorDefault,   // frees `data` with the buffer
            customBlockSource: nil, offsetToData: 0, dataLength: bytes,
            flags: 0, blockBufferOut: &block) == noErr, let block else {
            free(data)
            return nil
        }

        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(rate)),
            presentationTimeStamp: CMTime(value: frame, timescale: CMTimeScale(rate)),
            decodeTimeStamp: .invalid)
        var sampleSize = 4 * channels
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
                                        formatDescription: formatDescription,
                                        sampleCount: CMItemCount(frames),
                                        sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize,
                                        sampleBufferOut: &sample) == noErr else { return nil }
        return sample
    }
}
