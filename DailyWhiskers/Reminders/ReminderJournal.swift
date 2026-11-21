import Foundation
import CryptoKit

struct ReminderEntry: Codable, Equatable, Sendable {
    enum Phase: String, Codable { case intent, pending, cancelling }
    let id: String
    let target: ReminderTarget
    var phase: Phase
}

struct ReminderExposure: Codable, Equatable, Sendable {
    let day: String
    let from: Date
    var through: Date
}

struct ReminderJournal: Codable, Equatable, Sendable {
    var version = 3
    var enabled = false
    var time = ReminderTime()
    var entries: [ReminderEntry] = []
    // Optional when reading legacy v1 journals. New scheduler writes use v3. Retired IDs retain
    // target provenance even when iOS temporarily hides a cancelled request.
    // Never prune based on empty inventory or elapsed time alone.
    var retired: [ReminderEntry]?
    // Legacy v2 cancellation marker. A prior writer may already have removed
    // these IDs; never reinterpret this as the untouched-original permission path.
    var permissionSuspended: Bool?
    // These are possible presentations, never delivery receipts. They survive
    // edits, disable/re-enable and clearing Notification Center.
    var exposures: [ReminderExposure] = []
    var lastNow: Date?
    // Missing/null legacy state means unverified, never "never scheduled".
    // A false value records bounded authorized observations, not future silence.
    var cleanupPending: Bool?
    var needsCleanupVerification: Bool { version < 3 || cleanupPending != false }
    var clearDelivered = false
    var requiresRecovery = false

    func validate() throws {
        let known = entries + (retired ?? [])
        guard (version == 1 || version == 2 || version == 3), time.isValid,
              Set(known.map(\.id)).count == known.count,
              known.allSatisfy({ $0.id.hasPrefix(ReminderRequest.prefix) &&
                  TimeZone(identifier: $0.target.zone) != nil &&
                  ReminderCalendar.day($0.target.date, zone: TimeZone(identifier: $0.target.zone)!) == $0.target.day }),
              exposures.allSatisfy({ $0.through >= $0.from && ReminderCalendar.labels(start: $0.day, count: 1).count == 1 })
        else { throw ReminderStorageError.unreadable }
    }

    mutating func remember(_ entry: ReminderEntry, through: Date) {
        let end = max(entry.target.date, through)
        if let index = exposures.firstIndex(where: { $0.day == entry.target.day && $0.from == entry.target.date }) {
            exposures[index].through = max(exposures[index].through, end)
        } else {
            exposures.append(ReminderExposure(day: entry.target.day, from: entry.target.date, through: end))
        }
    }

    func blocks(_ target: ReminderTarget, now: Date) -> Bool {
        guard let zone = TimeZone(identifier: target.zone),
              let interval = ReminderCalendar.calendar(zone).dateInterval(of: .day, for: target.date) else { return true }
        let live = entries.filter { $0.target.date <= now }.map {
            ReminderExposure(day: $0.target.day, from: $0.target.date, through: now)
        }
        return (exposures + live).contains {
            $0.day == target.day || ($0.from < interval.end && $0.through >= interval.start)
        }
    }
}

enum ReminderStorageError: Error { case unreadable, verification, quarantined }

protocol ReminderJournalStore: Sendable {
    func load() throws -> ReminderJournal?
    func save(_ journal: ReminderJournal) throws
}

/// Separate local storage: authentication and clearing saved cards cannot erase
/// reminder eligibility. Atomic replacement + readback detects torn/corrupt data;
/// it is not a claim about surviving every device power-loss scenario.
struct FileReminderJournalStore: ReminderJournalStore {
    let directory: URL
    private var journalURL: URL { directory.appendingPathComponent("journal.json") }
    private var markerURL: URL { directory.appendingPathComponent("initialized") }
    private struct Envelope: Codable { let payload: Data; let sha256: String }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func load() throws -> ReminderJournal? {
        let exists = FileManager.default.fileExists(atPath: journalURL.path)
        let marker = FileManager.default.fileExists(atPath: markerURL.path)
        guard exists || marker else { return nil }
        guard exists, marker else { throw ReminderStorageError.unreadable }
        let data = try Data(contentsOf: journalURL) // An I/O failure may be temporary.
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw ReminderStorageError.unreadable
        }
        guard digest(envelope.payload) == envelope.sha256 else { throw ReminderStorageError.unreadable }
        guard let journal = try? JSONDecoder().decode(ReminderJournal.self, from: envelope.payload) else {
            throw ReminderStorageError.unreadable
        }
        try journal.validate()
        return journal
    }

    func save(_ journal: ReminderJournal) throws {
        try journal.validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Establish the sentinel first; an interrupted first save must not become
        // a fresh install with erased eligibility on the next launch.
        if !FileManager.default.fileExists(atPath: markerURL.path) {
            try Data("DW004-v1".utf8).write(to: markerURL, options: .atomic)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(journal)
        let data = try encoder.encode(Envelope(payload: payload, sha256: digest(payload)))
        try data.write(to: journalURL, options: .atomic)
        let handle = try FileHandle(forWritingTo: journalURL)
        defer { try? handle.close() }
        try handle.synchronize()
        guard try load() == journal else { throw ReminderStorageError.verification }
    }
}
