import Foundation
import SQLite3

final class SQLiteDatabase {
    private let handle: OpaquePointer?

    init(url: URL) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(url.path, &db, flags, nil)
        guard result == SQLITE_OK else {
            let message = SQLiteDatabase.errorMessage(from: db)
            sqlite3_close(db)
            throw ProcessMetricsStoreError.databaseOpenFailure(code: result, message: message)
        }
        handle = db
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        guard let handle else { return }
        var errorMessage: UnsafeMutablePointer<Int8>? = nil
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.flatMap { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorMessage)
            throw ProcessMetricsStoreError.executionFailure(code: result, message: message)
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            let message = SQLiteDatabase.errorMessage(from: handle)
            throw ProcessMetricsStoreError.statementPreparationFailure(message: message)
        }
        return SQLiteStatement(statement: statement)
    }

    func lastInsertRowID() -> Int64 {
        guard let handle else { return 0 }
        return sqlite3_last_insert_rowid(handle)
    }

    func rawHandle() -> OpaquePointer? {
        handle
    }

    private static func errorMessage(from handle: OpaquePointer?) -> String {
        guard let handle else { return "" }
        if let cString = sqlite3_errmsg(handle) {
            return String(cString: cString)
        }
        return ""
    }
}

final class SQLiteStatement {
    private let statement: OpaquePointer

    init(statement: OpaquePointer) {
        self.statement = statement
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func reset() {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
    }

    func bind(_ value: Double, at index: Int32) {
        sqlite3_bind_double(statement, index, value)
    }

    func bind(_ value: Int32, at index: Int32) {
        sqlite3_bind_int(statement, index, value)
    }

    func bind(_ value: Int64, at index: Int32) {
        sqlite3_bind_int64(statement, index, value)
    }

    func bind(_ value: UInt64, at index: Int32) {
        sqlite3_bind_int64(statement, index, Int64(bitPattern: value))
    }

    func bind(_ value: String, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    func bindNull(at index: Int32) {
        sqlite3_bind_null(statement, index)
    }

    func step() -> Int32 {
        sqlite3_step(statement)
    }

    func columnDouble(_ index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }

    func columnInt(_ index: Int32) -> Int32 {
        sqlite3_column_int(statement, index)
    }

    func columnInt64(_ index: Int32) -> Int64 {
        sqlite3_column_int64(statement, index)
    }

    func columnString(_ index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: text)
    }

    func rawStatement() -> OpaquePointer {
        statement
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
