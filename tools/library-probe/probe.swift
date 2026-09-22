// Phase 5 test program, part 4: can BGTools read a library while ShowTools
// writes to it? Two processes on a scratch copy of a library, never the
// real one:
//
//   library-probe writer <library> <seconds>
//       saves the first show over and over through ShowTools' own Library
//       code, as the app does. Each save changes slide lengths, and adds or
//       removes a slide, and stamps the show's name with
//       "probe <n> <slide count> <time>" in the same transaction.
//   library-probe reader <library> <seconds>
//       opens Library.sqlite READ-ONLY with plain SQLite (never Library.init,
//       which migrates and writes), polls PRAGMA data_version every 50 ms,
//       and on each change reads the show and its slides inside one read
//       transaction, decoding them with ShowToolsCore's own types.
//
// The reader reports: saves seen, torn reads (stamp's slide count ≠ slides
// read), busy/locked errors, undecodable settings, and how long after a save
// it noticed it.
import Foundation
import SQLite3

@main struct LibraryProbe {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4, let seconds = Double(args[3]) else {
            print("usage: library-probe writer|reader <library> <seconds>"); exit(2)
        }
        let root = URL(fileURLWithPath: args[2])
        switch args[1] {
        case "writer": try writer(root, seconds)
        case "reader": try reader(root, seconds)
        default: exit(2)
        }
    }

    static func writer(_ root: URL, _ seconds: Double) throws {
        let lib = try Library(root: root)
        guard var show = try lib.allShows().first, !show.slides.isEmpty else { print("no show"); exit(1) }
        let pool = show.slides
        let end = Date().addingTimeInterval(seconds)
        var n = 0
        while Date() < end {
            n += 1
            // Grow and shrink between 1 and the full set, changing lengths.
            let count = 1 + (n % pool.count)
            show.slides = pool.prefix(count).enumerated().map { i, s in
                var s = s
                s.settings.length = .seconds(Double(1 + (n + i) % 9))
                return s
            }
            show.name = "probe \(n) \(count) \(Date().timeIntervalSince1970)"
            show = try lib.saveShow(show)
            Thread.sleep(forTimeInterval: Double.random(in: 0.005...0.04))
        }
        print("writer: \(n) saves")
    }

    static func reader(_ root: URL, _ seconds: Double) throws {
        let path = root.appendingPathComponent("Library.sqlite").path
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            print("reader: can't open read-only: \(String(cString: sqlite3_errmsg(db)))"); exit(1)
        }
        defer { sqlite3_close(db) }

        func scalar(_ sql: String) -> Int64? {
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(st) }
            return sqlite3_step(st) == SQLITE_ROW ? sqlite3_column_int64(st, 0) : nil
        }
        func text(_ st: OpaquePointer?, _ i: Int32) -> String {
            sqlite3_column_text(st, i).map { String(cString: $0) } ?? ""
        }

        print("reader: schema version \(scalar("PRAGMA user_version") ?? -1), journal \(scalar("PRAGMA journal_mode") == nil ? "?" : "ok")")
        var lastVersion = scalar("PRAGMA data_version") ?? 0
        var seen = 0, torn = 0, busy = 0, undecodable = 0, lastStamp = -1, skippedStamps = 0
        var delays: [Double] = []
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            Thread.sleep(forTimeInterval: 0.05)
            guard let v = scalar("PRAGMA data_version") else { busy += 1; continue }
            if v == lastVersion { continue }
            lastVersion = v
            // One read transaction: the show and its slides from one snapshot.
            guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else { busy += 1; continue }
            var st: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT id, name, defaults FROM shows ORDER BY created_at, id LIMIT 1", -1, &st, nil)
            let rc = sqlite3_step(st)
            if rc == SQLITE_BUSY || rc == SQLITE_LOCKED { busy += 1 }
            guard rc == SQLITE_ROW else { sqlite3_finalize(st); sqlite3_exec(db, "COMMIT", nil, nil, nil); continue }
            let showID = sqlite3_column_int64(st, 0)
            let name = text(st, 1)
            if (try? JSONDecoder().decode(ShowDefaults.self, from: Data(text(st, 2).utf8))) == nil { undecodable += 1 }
            sqlite3_finalize(st)
            var sl: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT settings FROM slides WHERE show_id = ? ORDER BY position", -1, &sl, nil)
            sqlite3_bind_int64(sl, 1, showID)
            var slides = 0
            while true {
                let r = sqlite3_step(sl)
                if r == SQLITE_BUSY || r == SQLITE_LOCKED { busy += 1; break }
                guard r == SQLITE_ROW else { break }
                slides += 1
                if (try? JSONDecoder().decode(SlideSettings.self, from: Data(text(sl, 0).utf8))) == nil { undecodable += 1 }
            }
            sqlite3_finalize(sl)
            sqlite3_exec(db, "COMMIT", nil, nil, nil)

            let parts = name.split(separator: " ")
            guard parts.count == 4, parts[0] == "probe", let n = Int(parts[1]), let count = Int(parts[2]),
                  let t = Double(parts[3]) else { continue }
            seen += 1
            if count != slides { torn += 1 }
            if lastStamp >= 0, n > lastStamp + 1 { skippedStamps += n - lastStamp - 1 }
            lastStamp = n
            delays.append(Date().timeIntervalSince1970 - t)
        }
        delays.sort()
        func ms(_ x: Double) -> String { String(format: "%.0f ms", x * 1000) }
        print("reader: \(seen) changes read, torn \(torn), busy/locked \(busy), undecodable \(undecodable)")
        if !delays.isEmpty {
            print("reader: noticed a save after median \(ms(delays[delays.count / 2])), 95% within \(ms(delays[Int(Double(delays.count) * 0.95)])), worst \(ms(delays.last!))")
        }
        print("reader: saves not seen individually (several between two polls): \(skippedStamps)")
    }
}
