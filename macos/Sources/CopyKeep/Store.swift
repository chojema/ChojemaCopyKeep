import Foundation
import CryptoKit
import SQLite3
import Darwin

struct HistoryItem {
    let id: Int64
    let kind: String
    let payload: Data
    var title: String? = nil
    var text: String { String(data: payload, encoding: .utf8) ?? "" }
    var isSnippet: Bool { title != nil }
}

struct Preferences: Codable, Equatable {
    var language = "ko-KR"
    var moveUsed = true
    var limit = 200
    var keyCode: UInt32 = 6
    var modifiers: UInt32 = 4608 // control + shift
}

enum StoreError: Error { case database, invalidItem }

final class HistoryStore {
    static let maxItemBytes = 32 * 1024 * 1024
    static let maxTotalBytes = 256 * 1024 * 1024
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("history.db")
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(db); db = nil; throw StoreError.database
        }
        chmod(url.path, 0o600)
        sqlite3_busy_timeout(db, 3000)
        do {
            try execute("PRAGMA journal_mode=WAL; PRAGMA secure_delete=ON; CREATE TABLE IF NOT EXISTS history (id INTEGER PRIMARY KEY, kind TEXT NOT NULL, payload BLOB NOT NULL, hash TEXT NOT NULL UNIQUE, position INTEGER NOT NULL); CREATE TABLE IF NOT EXISTS settings (id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL);")
            try execute("CREATE TABLE IF NOT EXISTS snippets (id INTEGER PRIMARY KEY, title TEXT NOT NULL, payload BLOB NOT NULL)")
        } catch { sqlite3_close(db); db = nil; throw error }
    }

    deinit { sqlite3_close(db) }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw StoreError.database }
    }

    private func statement(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw StoreError.database }
        return stmt
    }

    private func finish(_ stmt: OpaquePointer) throws {
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.database }
    }

    func loadPreferences() throws -> Preferences {
        let stmt = try statement("SELECT payload FROM settings WHERE id=1")
        defer { sqlite3_finalize(stmt) }
        let result = sqlite3_step(stmt)
        if result == SQLITE_DONE { return Preferences() }
        guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(stmt, 0) else { throw StoreError.database }
        var value = (try? JSONDecoder().decode(Preferences.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0))))) ?? Preferences()
        if !Localization.languages.contains(value.language) { value.language = "ko-KR" }
        value.limit = min(1000, max(10, value.limit))
        return value
    }

    func savePreferences(_ value: Preferences) throws {
        let data = try JSONEncoder().encode(value)
        let stmt = try statement("INSERT OR REPLACE INTO settings VALUES (1, ?)")
        defer { sqlite3_finalize(stmt) }
        _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 1, $0.baseAddress, Int32(data.count), transient) }
        try finish(stmt)
    }

    @discardableResult
    func add(kind: String, payload: Data, limit: Int) throws -> Bool {
        guard ["text", "image"].contains(kind), !payload.isEmpty, payload.count <= Self.maxItemBytes else { throw StoreError.invalidItem }
        if kind == "text", String(data: payload, encoding: .utf8) == nil { throw StoreError.invalidItem }
        let hash = SHA256.hash(data: Data(kind.utf8) + payload).map { String(format: "%02x", $0) }.joined()
        try execute("BEGIN IMMEDIATE")
        do {
            let stmt = try statement("INSERT INTO history(kind,payload,hash,position) VALUES(?,?,?,(SELECT COALESCE(MAX(position),0)+1 FROM history)) ON CONFLICT(hash) DO UPDATE SET position=(SELECT COALESCE(MAX(position),0)+1 FROM history)")
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, kind, -1, transient)
            _ = payload.withUnsafeBytes { sqlite3_bind_blob(stmt, 2, $0.baseAddress, Int32(payload.count), transient) }
            sqlite3_bind_text(stmt, 3, hash, -1, transient)
            try finish(stmt)
            try prune(limit: limit)
            try execute("COMMIT")
            return true
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func list() throws -> [HistoryItem] {
        let stmt = try statement("SELECT id,kind,payload FROM history ORDER BY position DESC,id DESC")
        defer { sqlite3_finalize(stmt) }
        var items: [HistoryItem] = []
        while true {
            let result = sqlite3_step(stmt)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(stmt, 2), let kind = sqlite3_column_text(stmt, 1) else { throw StoreError.database }
            items.append(HistoryItem(id: sqlite3_column_int64(stmt, 0), kind: String(cString: kind),
                                     payload: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 2)))))
        }
        return items
    }

    func touch(_ id: Int64) throws {
        let stmt = try statement("UPDATE history SET position=(SELECT COALESCE(MAX(position),0)+1 FROM history) WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        try finish(stmt)
    }

    func snippets(matching query: String = "") throws -> [HistoryItem] {
        let stmt = try statement("SELECT id,title,payload FROM snippets WHERE instr(lower(title),lower(?1))>0 OR instr(lower(CAST(payload AS TEXT)),lower(?1))>0 ORDER BY id DESC")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, query, -1, transient)
        var items: [HistoryItem] = []
        while true {
            let result = sqlite3_step(stmt)
            if result == SQLITE_DONE { return items }
            guard result == SQLITE_ROW, let title = sqlite3_column_text(stmt, 1), let bytes = sqlite3_column_blob(stmt, 2) else { throw StoreError.database }
            items.append(HistoryItem(id: sqlite3_column_int64(stmt, 0), kind: "text",
                payload: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 2))), title: String(cString: title)))
        }
    }

    @discardableResult
    func saveSnippet(id: Int64? = nil, title: String, body: String) throws -> Int64 {
        guard id == nil || id! > 0, (1...80).contains(title.utf16.count), (1...65536).contains(body.utf16.count),
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.rangeOfCharacter(from: .newlines.union(CharacterSet(charactersIn: "\t\0"))) == nil,
              !body.contains("\0") else { throw StoreError.invalidItem }
        let stmt = try statement(id == nil ? "INSERT INTO snippets(title,payload) VALUES(?1,?2)" : "UPDATE snippets SET title=?1,payload=?2 WHERE id=?3")
        defer { sqlite3_finalize(stmt) }
        let data = Data(body.utf8)
        sqlite3_bind_text(stmt, 1, title, -1, transient)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 2, $0.baseAddress, Int32(data.count), transient) }
        if let id { sqlite3_bind_int64(stmt, 3, id) }
        try finish(stmt)
        guard id == nil || sqlite3_changes(db) == 1 else { throw StoreError.database }
        return id ?? sqlite3_last_insert_rowid(db)
    }

    func deleteSnippet(_ id: Int64) throws {
        let stmt = try statement("DELETE FROM snippets WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        try finish(stmt)
    }

    func delete(_ id: Int64) throws {
        let stmt = try statement("DELETE FROM history WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        try finish(stmt)
    }

    func clear() throws { try execute("DELETE FROM history; PRAGMA wal_checkpoint(TRUNCATE)") }

    func prune(limit: Int) throws {
        try execute("DELETE FROM history WHERE id NOT IN (SELECT id FROM history ORDER BY position DESC,id DESC LIMIT \(min(1000,max(10,limit))))")
        // Retain the newest items whose cumulative payload fits the byte budget.
        try execute("DELETE FROM history WHERE id IN (SELECT id FROM (SELECT id,SUM(length(payload)) OVER (ORDER BY position DESC,id DESC) AS bytes FROM history) WHERE bytes > \(Self.maxTotalBytes))")
    }
}
