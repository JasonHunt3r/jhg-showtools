import Foundation
import Accelerate

/// Which pictures look alike (plan, Phase 3b "Find Similar"), from each
/// picture's fingerprint: a unit-length vector (Vision's image feature
/// print, 768 floats). Two pictures' distance is the Euclidean distance
/// between their fingerprints, exactly as Vision's own `computeDistance`
/// (checked 2026-09-22): about 0.1–0.2 for a resized or recompressed copy,
/// 0.4–0.7 for shots of the same scene, around 1 for unrelated pictures.
///
/// Every pair closer than `reach` is found once, up front; grouping at any
/// tighter setting is then quick, so a slider can regroup as it moves.
public struct SimilarityIndex: Sendable {
    public struct Pair: Hashable, Sendable {
        public let a: Int64
        public let b: Int64
        public let distance: Float
    }

    /// The ids, in the order given (the grid's), for stable group order.
    public let ids: [Int64]
    /// Every pair within `reach`, closest first.
    public let pairs: [Pair]
    public let reach: Float

    public init(_ prints: [(id: Int64, print: [Float])], reach: Float = 0.8) {
        self.reach = reach
        let usable = prints.filter { !$0.print.isEmpty && $0.print.count == prints.first?.print.count }
        ids = usable.map(\.id)
        let n = usable.count, dim = usable.first?.print.count ?? 0
        guard n > 1, dim > 0 else { pairs = []; return }
        // All the fingerprints as rows of one matrix; for unit vectors,
        // distance² = |a|² + |b|² − 2 a·b, and a·b comes from one multiply.
        let flat = usable.flatMap(\.print)
        var norms = [Float](repeating: 0, count: n)
        for i in 0..<n { vDSP_svesq(Array(flat[(i * dim)..<((i + 1) * dim)]), 1, &norms[i], vDSP_Length(dim)) }
        var found: [Pair] = []
        let block = 256
        var dots = [Float](repeating: 0, count: block * n)
        var start = 0
        while start < n {
            let rows = min(block, n - start)
            // dots[r][j] = row (start + r) · row j
            flat.withUnsafeBufferPointer { m in
                cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(rows), Int32(n), Int32(dim),
                            1, m.baseAddress! + start * dim, Int32(dim), m.baseAddress!, Int32(dim),
                            0, &dots, Int32(n))
            }
            let limit = reach * reach
            for r in 0..<rows {
                let i = start + r
                for j in (i + 1)..<n {
                    let d2 = norms[i] + norms[j] - 2 * dots[r * n + j]
                    if d2 <= limit { found.append(Pair(a: usable[i].id, b: usable[j].id, distance: sqrt(max(d2, 0)))) }
                }
            }
            start += rows
        }
        pairs = found.sorted { $0.distance < $1.distance }
    }

    /// Groups of two or more pictures, each linked to another in its group
    /// by a pair closer than `within`. Groups come in the order of their
    /// first picture, and each keeps the given order inside it.
    public func groups(within: Float) -> [[Int64]] {
        var parent: [Int64: Int64] = [:]
        func root(_ x: Int64) -> Int64 {
            var r = x
            while let p = parent[r], p != r { r = p }
            var y = x
            while let p = parent[y], p != r { parent[y] = r; y = p }
            return r
        }
        for p in pairs {
            guard p.distance <= within else { break }
            let ra = root(p.a), rb = root(p.b)
            if ra != rb { parent[ra] = rb; parent[rb] = rb }
        }
        var members: [Int64: [Int64]] = [:]
        var order: [Int64] = []
        for id in ids where parent[id] != nil {
            let r = root(id)
            if members[r] == nil { order.append(r) }
            members[r, default: []].append(id)
        }
        return order.compactMap { members[$0] }.filter { $0.count > 1 }
    }

    /// The pictures closer to `id` than `within`, closest first.
    public func similar(to id: Int64, within: Float) -> [(id: Int64, distance: Float)] {
        pairs.lazy.filter { $0.distance <= within && ($0.a == id || $0.b == id) }
            .map { (id: $0.a == id ? $0.b : $0.a, distance: $0.distance) }
    }
}

/// Keep One (plan, Phase 3b): choosing one picture of a group, such as a
/// series that got imported, and letting the others go.
public enum KeepOne {
    /// The one to suggest: the most pixels, then the highest rating, then
    /// the one added first.
    public static func suggestedKeeper(_ items: [MediaItem]) -> MediaItem? {
        items.min { a, b in
            let pa = a.pixelWidth * a.pixelHeight, pb = b.pixelWidth * b.pixelHeight
            if pa != pb { return pa > pb }
            if a.rating != b.rating { return a.rating > b.rating }
            return a.ingestedAt < b.ingestedAt
        }
    }

    public struct Plan: Equatable, Sendable {
        /// What goes (out of the collection, or to the Trash).
        public var remove: [Int64]
        /// What stays because a show uses it.
        public var keptBecauseUsed: [Int64]
        /// The keeper's tags afterwards, if they change: its own, then the
        /// trashed ones' (only files going to the Trash hand theirs on).
        public var tags: [String]?
        /// The keeper's rating afterwards, if it goes up.
        public var rating: Int?
    }

    public static func plan(keeper: MediaItem, group: [MediaItem], used: Set<Int64>, trashing: Bool) -> Plan {
        let others = group.filter { $0.id != keeper.id }
        let going = others.filter { !used.contains($0.id) }
        var plan = Plan(remove: going.map(\.id), keptBecauseUsed: others.filter { used.contains($0.id) }.map(\.id))
        guard trashing else { return plan }
        var tags = keeper.tags
        for t in going.flatMap(\.tags) where !tags.contains(t) { tags.append(t) }
        if tags != keeper.tags { plan.tags = tags }
        let best = going.map(\.rating).max() ?? 0
        if best > keeper.rating { plan.rating = best }
        return plan
    }
}
