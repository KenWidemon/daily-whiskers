import Foundation
import SQLite3

enum CardStorageError: Error, LocalizedError {
    case unavailable, unsupportedSchema, database(Int32)
    var errorDescription: String? {
        switch self {
        case .unavailable: "This saved card is unavailable. Its original content could not be verified. Try again; no replacement artwork will be used."
        case .unsupportedSchema: "Saved Cards needs a newer version of Daily Whiskers. Your collection has not been changed."
        case .database: "Saved Cards could not be read or updated. Check available device storage and try again."
        }
    }
}

struct FavoriteRecord: Identifiable, Sendable {
    let id: String
    let quote: String
    let sequence: Int64
}

/// All durable content and references commit in one SQLite transaction, on one actor.
/// No identity, ownership, or lifecycle dependency on the authentication session.
actor CardRepository {
    static let shared = CardRepository(url: FileManager.default.urls(for: .applicationSupportDirectory,
        in: .userDomainMask)[0].appendingPathComponent("SavedCards/cards.sqlite"))
    let url: URL
    private var database: OpaquePointer?
    private let beforeCommit: (@Sendable () throws -> Void)?
    private var activeShares: [UUID: String] = [:]

    init(url: URL, beforeCommit: (@Sendable () throws -> Void)? = nil) {
        self.url = url
        self.beforeCommit = beforeCommit
    }
    deinit { if let database { sqlite3_close(database) } }

    private func open() throws {
        guard database == nil else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var directory = url.deletingLastPathComponent()
        var backup = URLResourceValues()
        backup.isExcludedFromBackup = false
        try directory.setResourceValues(backup)
        var connection: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else {
            if let connection { sqlite3_close(connection) }
            throw CardStorageError.database(result)
        }
        database = connection
        do {
            sqlite3_busy_timeout(connection, 3000)
            try execute("PRAGMA foreign_keys=ON")
            let version = try scalar("PRAGMA user_version")
            guard version <= 1 else { throw CardStorageError.unsupportedSchema }
            // Rollback journal keeps a closed backup self-contained, with FULL durability.
            try execute("PRAGMA journal_mode=DELETE")
            try execute("PRAGMA synchronous=FULL")
            if version == 0 {
                // Never interpret an unknown populated database as an empty installation.
                guard try scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'") == 0
                else { throw CardStorageError.unsupportedSchema }
                try transaction {
                    try execute("CREATE TABLE artwork(checksum TEXT PRIMARY KEY, bytes BLOB NOT NULL)")
                    try execute("CREATE TABLE snapshot(id TEXT PRIMARY KEY, metadata BLOB NOT NULL, artwork_checksum TEXT NOT NULL REFERENCES artwork(checksum))")
                    try execute("CREATE TABLE favorite(sequence INTEGER PRIMARY KEY AUTOINCREMENT, snapshot_id TEXT NOT NULL UNIQUE REFERENCES snapshot(id), quote TEXT NOT NULL)")
                    // Reserved reference ledger for #88. No day selection/allowance behavior here.
                    try execute("CREATE TABLE day_selection(local_date TEXT NOT NULL, slot TEXT NOT NULL, snapshot_id TEXT NOT NULL REFERENCES snapshot(id), time_zone TEXT NOT NULL, PRIMARY KEY(local_date,slot))")
                    try execute("PRAGMA user_version=1")
                }
            }
        } catch {
            sqlite3_close(connection)
            database = nil
            throw error
        }
    }

    func favorites() throws -> [FavoriteRecord] {
        try open()
        let statement = try prepare("SELECT snapshot_id,quote,sequence FROM favorite ORDER BY sequence DESC")
        defer { sqlite3_finalize(statement) }
        var records: [FavoriteRecord] = []
        while try step(statement) == SQLITE_ROW {
            records.append(FavoriteRecord(id: string(statement, 0), quote: string(statement, 1), sequence: sqlite3_column_int64(statement, 2)))
        }
        return records
    }

    func save(_ card: RetainedCard) throws {
        try open()
        try card.snapshot.validate(artwork: card.artwork)
        try transaction {
            // Same pixels/text with a different lossless encoding retain the first exact bytes.
            if try exists(card.snapshot.id) {
                _ = try load(card.snapshot.id)
            } else {
                try execute("INSERT OR IGNORE INTO artwork VALUES(?,?)", [.text(card.snapshot.artworkChecksum), .data(card.artwork)])
                let storedArtwork = try prepare("SELECT bytes FROM artwork WHERE checksum=?", [.text(card.snapshot.artworkChecksum)])
                defer { sqlite3_finalize(storedArtwork) }
                guard try step(storedArtwork) == SQLITE_ROW,
                      ArtworkIdentity.checksum(data(storedArtwork, 0)) == card.snapshot.artworkChecksum
                else { throw CardStorageError.unavailable }
                try execute("INSERT INTO snapshot VALUES(?,?,?)", [.text(card.snapshot.id),
                    .data(try JSONEncoder().encode(card.snapshot)), .text(card.snapshot.artworkChecksum)])
            }
            try execute("INSERT OR IGNORE INTO favorite(snapshot_id,quote) VALUES(?,?)", [.text(card.snapshot.id), .text(card.snapshot.quote)])
        }
    }

    func capture(_ card: DailyCard) throws -> RetainedCard {
        try CardSnapshot.capture(card: card, artwork: BundledCardArtwork.bytes(for: card))
    }

    func load(_ id: String) throws -> RetainedCard {
        try open()
        let statement = try prepare("SELECT s.metadata,a.bytes,s.artwork_checksum FROM snapshot s JOIN artwork a ON a.checksum=s.artwork_checksum WHERE s.id=?", [.text(id)])
        defer { sqlite3_finalize(statement) }
        guard try step(statement) == SQLITE_ROW else { throw CardStorageError.unavailable }
        let snapshot = try JSONDecoder().decode(CardSnapshot.self, from: data(statement, 0))
        let bytes = data(statement, 1)
        guard snapshot.id == id, snapshot.artworkChecksum == string(statement, 2) else { throw CardStorageError.unavailable }
        try snapshot.validate(artwork: bytes)
        return RetainedCard(snapshot: snapshot, artwork: bytes)
    }

    func remove(_ id: String) throws {
        try open()
        try transaction {
            try execute("DELETE FROM favorite WHERE snapshot_id=?", [.text(id)])
            try collectUnreferenced()
        }
    }

    func clearFavorites() throws {
        try open()
        try transaction {
            try execute("DELETE FROM favorite")
            try collectUnreferenced()
        }
    }

    // A share lease prevents future callers from deleting disk content while exporting.
    // Current UI also owns a complete in-memory RetainedCard through cancellation/retry.
    func beginShare(_ id: String) throws -> (UUID, RetainedCard) {
        let card = try load(id)
        let token = UUID()
        activeShares[token] = id
        return (token, card)
    }
    func endShare(_ token: UUID) throws {
        activeShares.removeValue(forKey: token)
        try open()
        try transaction { try collectUnreferenced() }
    }

    /// Consistent SQLite backup includes snapshots, artwork and the future date ledger.
    func backup(to destination: URL) throws {
        try open()
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw CardStorageError.unavailable }
        var target: OpaquePointer?
        let result = sqlite3_open(destination.path, &target)
        guard result == SQLITE_OK else { if let target { sqlite3_close(target) }; throw CardStorageError.database(result) }
        defer { sqlite3_close(target) }
        guard let backup = sqlite3_backup_init(target, "main", database, "main") else { throw CardStorageError.database(sqlite3_errcode(target)) }
        let copied = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard copied == SQLITE_DONE, finished == SQLITE_OK else { throw CardStorageError.database(finished == SQLITE_OK ? copied : finished) }
    }

    private func collectUnreferenced() throws {
        let pins = Array(Set(activeShares.values))
        let placeholders = pins.map { _ in "?" }.joined(separator: ",")
        try execute("DELETE FROM snapshot WHERE id NOT IN (SELECT snapshot_id FROM favorite) AND id NOT IN (SELECT snapshot_id FROM day_selection) AND id NOT IN (\(placeholders))", pins.map { .text($0) })
        try execute("DELETE FROM artwork WHERE checksum NOT IN (SELECT artwork_checksum FROM snapshot)")
    }
    private func exists(_ id: String) throws -> Bool {
        let statement = try prepare("SELECT 1 FROM snapshot WHERE id=?", [.text(id)])
        defer { sqlite3_finalize(statement) }
        return try step(statement) == SQLITE_ROW
    }
    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try beforeCommit?()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
    private enum Value { case text(String), data(Data) }
    private func prepare(_ sql: String, _ values: [Value] = []) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw CardStorageError.database(result) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let code: Int32
            switch value {
            case .text(let text): code = text.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, Int32(text.utf8.count), transient) }
            case .data(let data): code = data.withUnsafeBytes { sqlite3_bind_blob(statement, Int32(index + 1), $0.baseAddress, Int32(data.count), transient) }
            }
            guard code == SQLITE_OK else { sqlite3_finalize(statement); throw CardStorageError.database(code) }
        }
        return statement
    }
    private func step(_ statement: OpaquePointer) throws -> Int32 {
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW || result == SQLITE_DONE else { throw CardStorageError.database(result) }
        return result
    }
    private func execute(_ sql: String, _ values: [Value] = []) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        _ = try step(statement)
    }
    private func scalar(_ sql: String) throws -> Int64 {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard try step(statement) == SQLITE_ROW else { throw CardStorageError.unavailable }
        return sqlite3_column_int64(statement, 0)
    }
    private func string(_ statement: OpaquePointer, _ index: Int32) -> String {
        String(decoding: UnsafeBufferPointer(start: sqlite3_column_text(statement, index), count: Int(sqlite3_column_bytes(statement, index))), as: UTF8.self)
    }
    private func data(_ statement: OpaquePointer, _ index: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(statement, index) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    }
}
