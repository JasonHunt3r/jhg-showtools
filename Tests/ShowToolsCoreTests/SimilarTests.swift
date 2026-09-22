import XCTest
@testable import ShowToolsCore

final class SimilarTests: XCTestCase {
    /// A unit vector along `axis`, nudged by `nudge` along `toward`.
    func v(_ axis: Int, nudge: Float = 0, toward: Int = 7, dim: Int = 8) -> [Float] {
        var x = [Float](repeating: 0, count: dim)
        x[axis] = 1
        x[toward] += nudge
        let n = sqrt(x.reduce(0) { $0 + $1 * $1 })
        return x.map { $0 / n }
    }

    func testDistancesAreEuclideanAndOnlyWithinReachAreKept() {
        let idx = SimilarityIndex([(1, v(0)), (2, v(0, nudge: 0.1)), (3, v(1))], reach: 0.5)
        XCTAssertEqual(idx.pairs.count, 1, "1 and 3 are √2 apart, out of reach")
        let d = idx.pairs[0].distance
        let e = zip(v(0), v(0, nudge: 0.1)).reduce(Float(0)) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }.squareRoot()
        XCTAssertEqual(d, e, accuracy: 1e-5)
    }

    func testGroupsGrowAsTheSettingLoosensAndChainTogether() {
        // 1–2 close; 2–3 a bit further; 4 alone; 5–6 close.
        let idx = SimilarityIndex([(1, v(0)), (2, v(0, nudge: 0.1)), (3, v(0, nudge: 0.3)),
                                   (4, v(1)), (5, v(2)), (6, v(2, nudge: 0.05))])
        XCTAssertEqual(idx.groups(within: 0.08), [[5, 6]])
        XCTAssertEqual(idx.groups(within: 0.12), [[1, 2], [5, 6]])
        XCTAssertEqual(idx.groups(within: 0.35), [[1, 2, 3], [5, 6]], "3 joins through 2")
    }

    func testSimilarToOneIsClosestFirst() {
        let idx = SimilarityIndex([(1, v(0)), (2, v(0, nudge: 0.3)), (3, v(0, nudge: 0.1)), (4, v(1))])
        XCTAssertEqual(idx.similar(to: 1, within: 0.5).map(\.id), [3, 2])
        XCTAssertEqual(idx.similar(to: 4, within: 0.5).map(\.id), [])
    }

    func testMissingOrOddPrintsAreLeftOut() {
        let idx = SimilarityIndex([(1, v(0)), (2, []), (3, v(0, nudge: 0.05)), (4, [1, 0])])
        XCTAssertEqual(idx.ids, [1, 3])
        XCTAssertEqual(idx.groups(within: 0.5), [[1, 3]])
        XCTAssertTrue(SimilarityIndex([]).pairs.isEmpty)
    }

    func testManyPicturesAcrossBlocks() {
        // More than one 256-row block: 600 prints in 300 close pairs.
        var prints: [(id: Int64, print: [Float])] = []
        for k in 0..<300 {
            var a = [Float](repeating: 0, count: 600)
            a[k] = 1
            var b = a
            b[k + 300] = 0.05
            let n = Float(1 + 0.05 * 0.05).squareRoot()
            prints.append((Int64(2 * k), a))
            prints.append((Int64(2 * k + 1), b.map { $0 / n }))
        }
        let idx = SimilarityIndex(prints, reach: 0.3)
        XCTAssertEqual(idx.pairs.count, 300)
        XCTAssertEqual(idx.groups(within: 0.3).count, 300)
        XCTAssertEqual(idx.groups(within: 0.3).last, [598, 599])
    }
}

final class KeepOneTests: XCTestCase {
    func item(_ id: Int64, _ w: Int, _ h: Int, rating: Int = 0, tags: [String] = [], added: Double = 0) -> MediaItem {
        MediaItem(id: id, relativePath: "\(id).jpg", hash: "h\(id)", kind: .image, pixelWidth: w, pixelHeight: h,
                  duration: nil, ingestedAt: Date(timeIntervalSince1970: added), sourcePath: "", rating: rating, tags: tags)
    }

    func testTheLargestIsSuggestedThenTheBestRatedThenTheFirstAdded() {
        XCTAssertEqual(KeepOne.suggestedKeeper([item(1, 800, 600), item(2, 4000, 3000), item(3, 1000, 1000)])?.id, 2)
        XCTAssertEqual(KeepOne.suggestedKeeper([item(1, 10, 10, rating: 2), item(2, 10, 10, rating: 4)])?.id, 2)
        XCTAssertEqual(KeepOne.suggestedKeeper([item(1, 10, 10, added: 5), item(2, 10, 10, added: 1)])?.id, 2)
        XCTAssertNil(KeepOne.suggestedKeeper([]))
    }

    func testFilesAShowUsesStayAndTrashedOnesHandOnTagsAndRating() {
        let keeper = item(1, 10, 10, rating: 2, tags: ["beach"])
        let group = [keeper, item(2, 10, 10, rating: 5, tags: ["sunset", "beach"]), item(3, 10, 10, rating: 4, tags: ["used"]),
                     item(4, 10, 10, tags: ["dog"])]
        let p = KeepOne.plan(keeper: keeper, group: group, used: [3], trashing: true)
        XCTAssertEqual(p.remove, [2, 4])
        XCTAssertEqual(p.keptBecauseUsed, [3])
        XCTAssertEqual(p.tags, ["beach", "sunset", "dog"], "not the kept one's")
        XCTAssertEqual(p.rating, 5)
    }

    func testOutOfACollectionNothingIsHandedOn() {
        let keeper = item(1, 10, 10, rating: 1)
        let p = KeepOne.plan(keeper: keeper, group: [keeper, item(2, 10, 10, rating: 5, tags: ["x"])], used: [], trashing: false)
        XCTAssertEqual(p.remove, [2])
        XCTAssertNil(p.tags)
        XCTAssertNil(p.rating)
        // Nothing better to hand on: no change.
        let q = KeepOne.plan(keeper: item(1, 10, 10, rating: 5, tags: ["a"]), group: [item(1, 10, 10, rating: 5, tags: ["a"]),
                              item(2, 10, 10, rating: 3, tags: ["a"])], used: [], trashing: true)
        XCTAssertNil(q.tags)
        XCTAssertNil(q.rating)
    }
}
