import XCTest
@testable import ShowToolsCore

final class MediaMetadataTests: XCTestCase {
    /// No EXIF in a plain-written file, but the filesystem-level fields
    /// (size, format) still come back, and nothing crashes on a file with
    /// no camera data at all — the common case for a screenshot or a graphic.
    func testFileSizeAndFormatComeBackEvenWithoutExif() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("showtools-metadata-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("plain.jpg")
        try Data(repeating: 0, count: 128).write(to: url)

        let m = MediaMetadata.read(url)
        XCTAssertEqual(m.fileSize, 128)
        XCTAssertTrue(m.format?.localizedCaseInsensitiveContains("JPEG") == true, "got \(m.format ?? "nil")")
        XCTAssertNil(m.cameraMake)
        XCTAssertNil(m.dateTaken)
        XCTAssertNil(m.latitude)
    }
}
