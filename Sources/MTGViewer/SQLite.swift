import Foundation
import SQLite3

enum Bind {
    case int(Int64)
    case double(Double)
    case text(String)
    case null
}

struct DBError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thin wrapper over a single SQLite connection. Not thread-safe: use one connection per thread/queue.
final class SQLiteConn {
    private(set) var handle: OpaquePointer?

    init(path: String, readOnly: Bool) throws {
        let flags = (readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)) | SQLITE_OPEN_NOMUTEX
        var h: OpaquePointer?
        let rc = sqlite3_open_v2(path, &h, flags, nil)
        guard rc == SQLITE_OK, let h else {
            let msg = h.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            sqlite3_close(h)
            throw DBError(message: msg)
        }
        handle = h
    }

    deinit { sqlite3_close_v2(handle) }

    var lastError: String { String(cString: sqlite3_errmsg(handle)) }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let m = err.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(err)
            throw DBError(message: m)
        }
    }

    func prepare(_ sql: String) throws -> Statement { try Statement(conn: self, sql: sql) }

    func scalarText(_ sql: String) -> String? {
        guard let st = try? prepare(sql), st.step() else { return nil }
        return st.text(0)
    }
}

final class Statement {
    private var stmt: OpaquePointer?
    private let conn: SQLiteConn

    init(conn: SQLiteConn, sql: String) throws {
        self.conn = conn
        if sqlite3_prepare_v2(conn.handle, sql, -1, &stmt, nil) != SQLITE_OK {
            throw DBError(message: conn.lastError + " — " + sql.prefix(300))
        }
    }

    deinit { sqlite3_finalize(stmt) }

    func bind(_ binds: [Bind]) {
        for (i, b) in binds.enumerated() { bind(Int32(i + 1), b) }
    }

    func bind(_ i: Int32, _ b: Bind) {
        switch b {
        case .int(let v): sqlite3_bind_int64(stmt, i, v)
        case .double(let v): sqlite3_bind_double(stmt, i, v)
        case .text(let s): sqlite3_bind_text(stmt, i, s, -1, SQLITE_TRANSIENT)
        case .null: sqlite3_bind_null(stmt, i)
        }
    }

    func reset() {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
    }

    /// Steps once; returns true when a row is available.
    @discardableResult
    func step() -> Bool { sqlite3_step(stmt) == SQLITE_ROW }

    func run() throws {
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw DBError(message: conn.lastError) }
    }

    func int64(_ c: Int32) -> Int64 { sqlite3_column_int64(stmt, c) }
    func int(_ c: Int32) -> Int { Int(sqlite3_column_int64(stmt, c)) }
    func double(_ c: Int32) -> Double { sqlite3_column_double(stmt, c) }
    func optDouble(_ c: Int32) -> Double? {
        sqlite3_column_type(stmt, c) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, c)
    }
    func text(_ c: Int32) -> String {
        guard let p = sqlite3_column_text(stmt, c) else { return "" }
        return String(cString: p)
    }
}
