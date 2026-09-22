import Foundation
import SQLite3

public struct DatabaseError: Error, CustomStringConvertible {
    public let description: String
}

/// A thin wrapper over the SQLite that ships with macOS. No dependency: the
/// app needs a handful of tables and plain SQL, not an ORM.
final class Database {
    private let handle: OpaquePointer

    init(path: String) throws {
        var h: OpaquePointer?
        guard sqlite3_open(path, &h) == SQLITE_OK, let h else {
            let msg = h.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(h)
            throw DatabaseError(description: "Can't open database: \(msg)")
        }
        handle = h
        try exec("PRAGMA foreign_keys = ON")
        try exec("PRAGMA journal_mode = WAL")
    }

    deinit { sqlite3_close(handle) }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw DatabaseError(description: "\(msg) — in: \(sql)")
        }
    }

    func prepare(_ sql: String) throws -> Statement {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw DatabaseError(description: "\(errorMessage) — in: \(sql)")
        }
        return Statement(stmt, db: self)
    }

    /// Run `body` in a transaction; roll back if it throws.
    /// Inside another transaction, it joins that one: the outer one commits
    /// or rolls back the lot.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        if sqlite3_get_autocommit(handle) == 0 { return try body() }
        try exec("BEGIN IMMEDIATE")
        do {
            let r = try body()
            try exec("COMMIT")
            return r
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    var lastInsertID: Int64 { sqlite3_last_insert_rowid(handle) }
    var errorMessage: String { String(cString: sqlite3_errmsg(handle)) }

    var userVersion: Int {
        get { (try? prepare("PRAGMA user_version").firstInt()) ?? 0 }
    }
}

enum SQLValue {
    case int(Int64), double(Double), text(String), null
}

final class Statement {
    private let stmt: OpaquePointer
    private unowned let db: Database

    init(_ stmt: OpaquePointer, db: Database) {
        self.stmt = stmt
        self.db = db
    }

    deinit { sqlite3_finalize(stmt) }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    @discardableResult
    func bind(_ values: SQLValue...) -> Statement {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        for (i, v) in values.enumerated() {
            let idx = Int32(i + 1)
            switch v {
            case .int(let x): sqlite3_bind_int64(stmt, idx, x)
            case .double(let x): sqlite3_bind_double(stmt, idx, x)
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, Self.transient)
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }
        return self
    }

    /// True while there is a row to read.
    func step() throws -> Bool {
        switch sqlite3_step(stmt) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw DatabaseError(description: db.errorMessage)
        }
    }

    func run() throws {
        while try step() {}
        sqlite3_reset(stmt)
    }

    func firstInt() throws -> Int? {
        defer { sqlite3_reset(stmt) }
        return try step() ? Int(int(0)) : nil
    }

    func firstText() throws -> String? {
        defer { sqlite3_reset(stmt) }
        return try step() ? text(0) : nil
    }

    func int(_ col: Int32) -> Int64 { sqlite3_column_int64(stmt, col) }
    func double(_ col: Int32) -> Double { sqlite3_column_double(stmt, col) }
    func isNull(_ col: Int32) -> Bool { sqlite3_column_type(stmt, col) == SQLITE_NULL }
    func text(_ col: Int32) -> String {
        guard let p = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: p)
    }
}
