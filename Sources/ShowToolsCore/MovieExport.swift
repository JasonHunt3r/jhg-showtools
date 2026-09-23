import Foundation
import AVFoundation
import CoreGraphics

// Video export (plan, `spec/video-export.md`). E1: what a movie is asked
// for — its size, its frame rate and its codec — with the rules encoders
// impose kept in one place, so the panel and the writer can't disagree.

/// The three formats offered, all of them the OS's own and all hardware
/// accelerated on Jason's Mac (measured with `VTCopyVideoEncoderList`).
public enum MovieCodec: String, CaseIterable, Codable, Sendable {
    case h264
    case hevc
    case proRes422HQ

    public var avCodec: AVVideoCodecType {
        switch self {
        case .h264: .h264
        case .hevc: .hevc
        case .proRes422HQ: .proRes422HQ
        }
    }

    /// ProRes is a QuickTime codec: `.mp4` can't carry it, and an
    /// `AVAssetWriter` asked for that pair fails at the first sample.
    public var container: MovieContainer { self == .proRes422HQ ? .mov : .mp4 }

    public var fileExtension: String { container.fileExtension }

    public var name: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC"
        case .proRes422HQ: "ProRes 422 HQ"
        }
    }

    /// What the format popup reads: "H.264 (.mp4)".
    public var menuTitle: String { "\(name) (.\(fileExtension))" }

    /// How the sound is stored beside the picture. ProRes is a mastering
    /// codec and its `.mov` takes uncompressed sound, so it gets Linear
    /// PCM; the delivery formats get AAC, which is what an `.mp4` carries
    /// everywhere.
    public func audioSettings(sampleRate: Double, channels: AVAudioChannelCount) -> [String: Any] {
        switch self {
        case .proRes422HQ:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: Int(channels),
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        case .h264, .hevc:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: Int(channels),
                AVEncoderBitRateKey: 192_000,
            ]
        }
    }
}

public enum MovieContainer: String, Codable, Sendable {
    case mp4
    case mov

    public var fileType: AVFileType { self == .mp4 ? .mp4 : .mov }
    public var fileExtension: String { rawValue }
}

/// The frame rates offered. Integers on purpose: a show's clock is
/// seconds, not a broadcast timebase, so there is no 23.976 here.
public enum MovieFrameRate: Int, CaseIterable, Codable, Sendable {
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60

    public static let `default` = MovieFrameRate.fps30

    public var fps: Int { rawValue }
    /// One frame, exactly: `rawValue` ticks of a `rawValue` timescale.
    public var frameDuration: CMTime { CMTime(value: 1, timescale: CMTimeScale(rawValue)) }
    public var seconds: Double { 1 / Double(rawValue) }
    public var name: String { "\(rawValue) fps" }
}

/// What to export, and how big. The show's own shape is the default, and
/// `MovieExportSettings` never widens or crops to reach another shape — see
/// `plan(showAspect:)`.
public struct MovieExportSettings: Hashable, Sendable {
    /// The movie's pixel size, as asked for. Always even: encoders require
    /// it, and a frame that isn't is rejected or quietly resized.
    public private(set) var size: CGSize
    public var frameRate: MovieFrameRate
    public var codec: MovieCodec

    public init(size: CGSize, frameRate: MovieFrameRate = .default, codec: MovieCodec = .h264) {
        self.size = MovieExportSettings.even(size)
        self.frameRate = frameRate
        self.codec = codec
    }

    public mutating func setSize(_ size: CGSize) { self.size = MovieExportSettings.even(size) }

    /// Rounded to even, and never smaller than 2×2. Rounding down rather
    /// than to nearest keeps a chosen standard size (1920×1080) exactly
    /// itself and a screen's odd size just inside it.
    public static func even(_ size: CGSize) -> CGSize {
        func e(_ v: CGFloat) -> CGFloat {
            guard v.isFinite else { return 2 }
            return max(2, (v / 2).rounded(.down) * 2)
        }
        return CGSize(width: e(size.width), height: e(size.height))
    }

    /// Where the show's picture sits inside the movie's frame.
    ///
    /// Shows are composed for a screen, and Jason's is roughly 16:10. A
    /// movie asked for at another shape therefore gets the whole picture,
    /// fitted and letterboxed (or pillarboxed) — never a crop, which would
    /// cut every slide and shift every Ken Burns move. The picture itself
    /// is composed at `picture.size`, so it is even too.
    public func plan(showAspect: CGFloat) -> MovieRenderPlan {
        let canvas = size
        guard showAspect.isFinite, showAspect > 0, canvas.height > 0 else {
            return MovieRenderPlan(canvas: canvas, picture: CGRect(origin: .zero, size: canvas))
        }
        let canvasAspect = canvas.width / canvas.height
        var w = canvas.width, h = canvas.height
        if abs(canvasAspect - showAspect) > 1e-6 {
            if showAspect > canvasAspect { h = canvas.width / showAspect }   // letterbox
            else { w = canvas.height * showAspect }                          // pillarbox
        }
        let fitted = MovieExportSettings.even(CGSize(width: w, height: h))
        let origin = CGPoint(x: ((canvas.width - fitted.width) / 2).rounded(),
                             y: ((canvas.height - fitted.height) / 2).rounded())
        return MovieRenderPlan(canvas: canvas, picture: CGRect(origin: origin, size: fitted))
    }
}

/// The movie's frame, and the rectangle of it the show is drawn into.
/// `isLetterboxed` is what the panel says out loud.
public struct MovieRenderPlan: Hashable, Sendable {
    public var canvas: CGSize
    public var picture: CGRect

    public var isLetterboxed: Bool { picture.size != canvas }
}

/// The sizes the panel offers besides the show's own.
public struct MovieSizePreset: Hashable, Sendable, Identifiable {
    public var name: String
    public var size: CGSize

    public var id: String { name }

    public init(name: String, size: CGSize) {
        self.name = name
        self.size = MovieExportSettings.even(size)
    }

    public static let standard: [MovieSizePreset] = [
        MovieSizePreset(name: "720p", size: CGSize(width: 1280, height: 720)),
        MovieSizePreset(name: "1080p", size: CGSize(width: 1920, height: 1080)),
        MovieSizePreset(name: "4K", size: CGSize(width: 3840, height: 2160)),
    ]

    /// The show's own size, named so the panel can show it as the default.
    public static func show(_ size: CGSize) -> MovieSizePreset {
        MovieSizePreset(name: "Match the show", size: size)
    }
}
