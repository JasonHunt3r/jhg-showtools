import XCTest
@testable import ShowToolsCore

/// Import (plan, Phase 4b). An extension of the export tests, for their
/// media and show helpers.
extension SetlistTests {

    /// What the app does between `filesToImport` and `makeShow`: copy each
    /// file in, skipping one the library already has.
    func importFiles(_ urls: [URL], into lib: Library) async throws -> Set<Int64> {
        var ids: Set<Int64> = []
        for u in urls {
            let hash = try Ingest.sha256(of: u)
            if try lib.itemID(forHash: hash) != nil { continue }
            let c = try await Ingest.copyIn(u, expectedHash: hash, mediaDir: lib.mediaURL)
            ids.insert(try lib.insertItem(relativePath: c.relativePath, hash: hash, probe: c.probe, sourcePath: u.path).id)
        }
        return ids
    }

    func runImport(_ folder: URL, into lib: Library, collectionID: Int64? = nil) async throws -> SetlistImport.Result {
        let r = try await SetlistImport.read(folder)
        let imported = try await importFiles(try SetlistImport.filesToImport(r, lib: lib), into: lib)
        return try SetlistImport.makeShow(r, in: lib, collectionID: collectionID, imported: imported)
    }

    func export(_ show: Show, _ lib: Library, strip: Bool = true) async throws -> URL {
        let out = dir.appendingPathComponent("Exports-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let opts = SetlistExport.Options(stripMetadata: strip)
        return try await SetlistExport.write(try SetlistExport.plan(show, from: lib, options: opts), into: out, options: opts).folder
    }

    /// The show as the import should rebuild it: same settings, with each
    /// slide's exported id kept as its auto Ken Burns seed.
    func expectedSlides(_ show: Show) -> [SlideSettings] {
        show.slides.map { var s = $0.settings; s.kenBurnsSeed = s.kenBurnsSeed ?? $0.id; return s }
    }

    func testARoundTripIntoTheSameLibraryReusesItsFiles() async throws {
        var (lib, show, _) = try await makeShow()
        show.slides[1].settings.kenBurns = .auto
        show.defaults.length = 6.5
        show.editor.rangeIn = 0.5
        show = try lib.saveShow(show)
        let folder = try await export(show, lib)

        let r = try await SetlistImport.read(folder)
        XCTAssertEqual(r.problems, [])
        XCTAssertEqual(try SetlistImport.filesToImport(r, lib: lib), [], "stripped copies still match by library hash")
        let result = try SetlistImport.makeShow(r, in: lib, collectionID: nil, imported: [])
        let got = result.show
        XCTAssertEqual(got.name, "Beach Trip")
        XCTAssertNotEqual(got.id, show.id)
        XCTAssertEqual(got.slides.map(\.itemID), show.slides.map(\.itemID))
        XCTAssertEqual(got.slides.map(\.settings), expectedSlides(show))
        XCTAssertEqual(got.defaults, show.defaults)
        XCTAssertEqual(got.music, show.music)
        XCTAssertEqual(got.overlays, show.overlays)
        XCTAssertEqual(got.markers, show.markers)
        XCTAssertEqual(got.rows, show.rows)
        XCTAssertEqual(got.editor, show.editor)
        XCTAssertEqual(result.reused, 4)
        XCTAssertEqual(result.problems, [])
    }

    func testARoundTripIntoANewLibraryBringsFilesRatingsTagsAndTheSameAutoMoves() async throws {
        var (lib, show, items) = try await makeShow()
        show.slides[1].settings.kenBurns = .auto
        show = try lib.saveShow(show)
        let folder = try await export(show, lib)

        let other = try Library(root: dir.appendingPathComponent("Other.noindex"))
        let col = try other.createCollection(name: "Beach Trip")
        let result = try await runImport(folder, into: other, collectionID: col.id)
        let got = result.show
        XCTAssertEqual(result.problems, [])
        XCTAssertEqual(result.reused, 0)
        let newItems = Dictionary(uniqueKeysWithValues: try other.allItems().map { ($0.id, $0) })
        XCTAssertEqual(newItems.count, 4, "the two beach slides share one stripped file")
        XCTAssertEqual(got.slides[0].itemID, got.slides[2].itemID)
        XCTAssertEqual(got.slides.map(\.settings), expectedSlides(show))
        XCTAssertEqual(newItems[got.slides[1].itemID]?.rating, 4)
        XCTAssertEqual(newItems[got.slides[1].itemID]?.tags, ["Summer"])
        XCTAssertEqual(newItems[got.music[0].itemID]?.kind, .audio)
        XCTAssertEqual(newItems[got.overlays[0].itemID]?.kind, .animatedImage)
        XCTAssertEqual(got.collectionID, col.id)

        // The same auto move as in the first library.
        let before = ShowTimeline.autoKenBurns(seed: show.slides[1].id)
        let after = ShowTimeline.autoKenBurns(seed: got.slides[1].settings.kenBurnsSeed ?? got.slides[1].id)
        XCTAssertEqual(before, after)

        // Importing it again reuses everything and gives nothing new ratings.
        try other.setRating(1, for: [got.slides[1].itemID])
        let again = try await runImport(folder, into: other)
        XCTAssertEqual(again.reused, 4)
        // Its slides have new ids, and still the same auto move.
        XCTAssertNotEqual(again.show.slides[1].id, show.slides[1].id)
        XCTAssertEqual(ShowTimeline.autoKenBurns(seed: again.show.slides[1].settings.kenBurnsSeed ?? 0), before)
        XCTAssertEqual(try other.allItems().first { $0.id == got.slides[1].itemID }?.rating, 1)
    }

    func testEditsInTheTSVWinAndUnchangedCellsKeepExactValues() async throws {
        var (lib, show, _) = try await makeShow()
        show.slides[0].settings.kenBurns = .custom(KenBurns(start: .centred, end: KenBurnsFrame(x: 0.123456, y: 0.4, zoom: 1.4),
                                                            easing: .linear, acceleration: 0.3))
        show.slides[2].settings.rotation?.pivotStart = ImagePoint(x: 0.2, y: 0.2)
        show = try lib.saveShow(show)
        let folder = try await export(show, lib)
        let tsvURL = folder.appendingPathComponent("show.tsv")
        var lines = try String(contentsOf: tsvURL, encoding: .utf8).components(separatedBy: "\n")
        func row(_ prefix: String) -> Int { lines.firstIndex { $0.hasPrefix(prefix) }! }
        // Slide 3 first, with a new rotation; slide 2 deleted; slide 1 with
        // a new length and an unreadable transition; a new default length.
        var third = lines[row("003_")].components(separatedBy: "\t")
        third[6] = "0 to 180"
        var first = lines[row("001_")].components(separatedBy: "\t")
        first[1] = "3"; first[2] = "swipe sideways 1"
        let header = row("file\t")
        lines[row("# default_length")] = "# default_length\t4"
        lines = Array(lines[...header]) + [third.joined(separator: "\t"), first.joined(separator: "\t")]
        try lines.joined(separator: "\n").write(to: tsvURL, atomically: true, encoding: .utf8)

        let got = try await runImport(folder, into: lib)
        XCTAssertEqual(got.show.slides.count, 2)
        XCTAssertEqual(got.show.defaults.length, 4)
        let s3 = got.show.slides[0].settings, s1 = got.show.slides[1].settings
        XCTAssertEqual(s3.rotation?.endAngle, 180)
        XCTAssertEqual(s3.rotation?.pivotStart, ImagePoint(x: 0.2, y: 0.2), "what the cell doesn't carry is kept")
        XCTAssertEqual(s1.length, .seconds(3))
        XCTAssertEqual(s1.transition, show.slides[0].settings.transition, "an unreadable cell keeps the value")
        XCTAssertEqual(s1.kenBurns, show.slides[0].settings.kenBurns, "a rounded but unchanged cell keeps the exact value")
        XCTAssertEqual(got.problems.count, 1)
        XCTAssertTrue(got.problems[0].contains("transition"), got.problems[0])
    }

    func testATSVWithoutJSONStillBuildsTheShow() async throws {
        let (lib, show, _) = try await makeShow()
        let folder = try await export(show, lib)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("show.json"))
        let other = try Library(root: dir.appendingPathComponent("Other.noindex"))
        let got = try await runImport(folder, into: other)
        XCTAssertEqual(got.show.slides.count, 3)
        XCTAssertEqual(got.show.slides[0].settings.length, .seconds(8))
        XCTAssertEqual(got.show.slides[1].settings.transition, Transition(style: .swipe, duration: 0.5))
        XCTAssertEqual(got.show.slides[2].settings.rotation?.endAngle, 90)
        XCTAssertEqual(got.show.music, [], "songs are in the JSON only")
    }

    func testAPlainFolderBecomesAShowInNameOrder() async throws {
        let folder = dir.appendingPathComponent("Holiday.noindex")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (n, c) in [("img10.png", 0.1), ("img2.png", 0.2), ("img1.png", 0.3)] {
            try FileManager.default.moveItem(at: try writeImage(n, .png, colour: c), to: folder.appendingPathComponent(n))
        }
        try FileManager.default.moveItem(at: try writeSong(), to: folder.appendingPathComponent("song.m4a"))
        let lib = try Library(root: dir.appendingPathComponent("Lib.noindex"))
        let r = try await SetlistImport.read(folder)
        XCTAssertEqual(r.slides.map(\.file), ["img1.png", "img2.png", "img10.png"])
        XCTAssertEqual(r.problems.count, 1, "\(r.problems)")
        let got = try await runImport(folder, into: lib)
        XCTAssertEqual(got.show.name, "Holiday")
        XCTAssertEqual(got.show.slides.count, 3)
        XCTAssertTrue(got.show.slides.allSatisfy { $0.settings == SlideSettings() })
    }

    func testAnEmptyFolderIsNothingToImport() async throws {
        do { _ = try await SetlistImport.read(dir); XCTFail() } catch let e as SetlistImport.Failure {
            XCTAssertEqual(e, .nothingToImport)
        }
    }

    func testEveryCellReadsBackAsWritten() throws {
        var r = Rotation(); r.mode = .speed; r.speed = -12.5; r.startAngle = 10
        XCTAssertEqual(try SetlistTSV.parseRotation(SetlistTSV.rotation(r), base: nil), r)
        let t = Transition(style: .pageCurl, duration: 1.25, direction: .down, lead: 0.5)
        XCTAssertEqual(try SetlistTSV.parseTransition(SetlistTSV.transition(t)), t)
        XCTAssertEqual(try SetlistTSV.parseTransition("Dissolve 2"), Transition(style: .dissolve, duration: 2))
        XCTAssertEqual(try SetlistTSV.parseLength("clip"), .clip)
        XCTAssertEqual(try SetlistTSV.parseColour("#FF8000"), SRGBColor(red: 1, green: 128.0 / 255, blue: 0))
        XCTAssertEqual(try SetlistTSV.parseKenBurns(start: "0.5,0.5,1", end: "", base: nil),
                       .custom(KenBurns(start: .centred, end: .centred)))
        for bad in ["", "wobble 1", "dissolve", "dissolve fast", "swipe left 1 lead"] {
            XCTAssertThrowsError(try SetlistTSV.parseTransition(bad), bad)
        }
        XCTAssertThrowsError(try SetlistTSV.parseLength("0"))
        XCTAssertThrowsError(try SetlistTSV.parseRotation("spin", base: nil))

        let table = SetlistTSV.parse("# ShowTools setlist v1\r\n# loop\tno\r\nFile\tLength\r\n\"a.jpg\"\t3\r\nb.jpg\r\n")
        XCTAssertEqual(table.meta["loop"], "no")
        XCTAssertEqual(table.header, ["file", "length"])
        XCTAssertEqual(table.rows.map { $0.cells["file"] }, ["a.jpg", "b.jpg"])
        XCTAssertEqual(table.rows.map { $0.cells["length"] }, ["3", ""])
    }
}
