import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Everything the Info panel shows beyond what's already in the database
/// (dimensions, kind): read fresh from the file each time it's asked for,
/// never cached — the file is the source of truth, and it can only get
/// more accurate by being re-read. A field that isn't present, or isn't in
/// a still image at all, comes back nil and the panel simply doesn't show
/// its row.
public struct MediaMetadata: Sendable {
    public var fileSize: Int64?
    /// A human name for the format ("JPEG image", "QuickTime movie"), not
    /// the raw extension.
    public var format: String?
    public var dateTaken: Date?
    public var cameraMake: String?
    public var cameraModel: String?
    public var lensModel: String?
    /// Seconds.
    public var exposureTime: Double?
    public var fNumber: Double?
    public var iso: Int?
    /// Millimetres.
    public var focalLength: Double?
    public var latitude: Double?
    public var longitude: Double?

    public init() {}

    public static func read(_ url: URL) -> MediaMetadata {
        var m = MediaMetadata()
        m.fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
        m.format = UTType(filenameExtension: url.pathExtension)?.localizedDescription

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return m }

        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            m.cameraMake = tiff[kCGImagePropertyTIFFMake] as? String
            m.cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
        }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            m.exposureTime = exif[kCGImagePropertyExifExposureTime] as? Double
            m.fNumber = exif[kCGImagePropertyExifFNumber] as? Double
            m.iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
            m.focalLength = exif[kCGImagePropertyExifFocalLength] as? Double
            m.lensModel = exif[kCGImagePropertyExifLensModel] as? String
            if let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                let f = DateFormatter()
                f.dateFormat = "yyyy:MM:dd HH:mm:ss"
                f.timeZone = TimeZone(identifier: "UTC")   // EXIF carries no zone; read as given, no shift.
                m.dateTaken = f.date(from: s)
            }
        }
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           var lat = gps[kCGImagePropertyGPSLatitude] as? Double,
           var lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { lat = -lat }
            if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lon = -lon }
            m.latitude = lat
            m.longitude = lon
        }
        return m
    }
}
