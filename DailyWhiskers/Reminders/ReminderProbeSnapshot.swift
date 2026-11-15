#if DEBUG && CI_SMOKE_TESTING && DW_REMINDER_ENABLE_PROBE && targetEnvironment(simulator)
import Foundation
import Darwin

/// Independent transport for the existing marker boundaries, never a journal.
/// A retained file is only a prefix. Atomic replacement is not crash durability.
struct ReminderProbeEvent: Codable {
    let schema: Int
    let run: String
    let pid: Int32
    let seq: Int
    let tick: Double
    let stage: String
    let id: Int
    let command: String
    let requested: Int
    let enabled: Bool
    let authorization: String
    let queued: Int
    let hasCoverage: Bool
    let hasMessage: Bool
    let storageBlocked: Bool
    let cleanupPending: Bool
    let busy: Bool
    let loaded: Bool
    let operations: Int
}

struct ReminderProbePrefix: Encodable {
    let witnessSchema = 1
    let kind = "prefix"
    let run: String
    let pid: Int32
    let eventCount: Int
    let lastSequence: Int
    let replacementAttempts: Int
    let overflow: Bool
    // The current write cannot report its own elapsed time without another write.
    // These measurements cover prior successful writes, not the retained write.
    let measuredWrites: Int
    let writeNanoseconds: UInt64
    let events: [ReminderProbeEvent]
}

@MainActor
final class ReminderProbeSnapshotWriter {
    static let maxEvents = 64
    static let maxBytes = 64 * 1024
    static let maxAttempts = 65
    private let run: String
    private let pid: Int32
    private let replace: (Data) throws -> Void
    private let encode: (ReminderProbePrefix) throws -> Data
    private let clock: () -> UInt64
    private var events: [ReminderProbeEvent] = []
    private(set) var stopped = false
    private(set) var attempts = 0
    private(set) var successfulWrites = 0
    private(set) var totalWriteNanoseconds: UInt64 = 0
    private(set) var lastWriteNanoseconds: UInt64 = 0

    // Injectable sinks/encoder/clock exercise this exact writer offline. App use
    // supplies only the app-private directory; no file is read to initialize it.
    init(run: String, pid: Int32, directory: URL,
         replace: ((Data) throws -> Void)? = nil,
         encode: @escaping (ReminderProbePrefix) throws -> Data = { value in
             let encoder = JSONEncoder()
             encoder.outputFormatting = [.sortedKeys]
             return try encoder.encode(value)
         }, clock: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }) {
        self.run = run
        self.pid = pid
        self.encode = encode
        self.clock = clock
        let store = ReminderProbeAtomicStore(directory: directory, name: run + ".json")
        self.replace = replace ?? { try store.replace($0) }
        stopped = UUID(uuidString: run)?.uuidString != run || pid <= 0
    }

    func append(_ event: ReminderProbeEvent) {
        guard !stopped else { return }
        guard event.run == run, event.pid == pid, event.schema == 1,
              event.seq == events.count + 1, event.tick.isFinite, event.tick >= 0,
              attempts < Self.maxAttempts else { stopped = true; return }
        let start = clock()
        var overflow = events.count == Self.maxEvents
        if !overflow { events.append(event) }
        attempts += 1
        func snapshot() -> ReminderProbePrefix {
            ReminderProbePrefix(run: run, pid: pid, eventCount: events.count,
                lastSequence: events.last?.seq ?? 0, replacementAttempts: attempts,
                overflow: overflow, measuredWrites: successfulWrites,
                writeNanoseconds: totalWriteNanoseconds, events: events)
        }
        do {
            var bytes = try encode(snapshot())
            if bytes.count > Self.maxBytes && !overflow {
                events.removeLast()
                overflow = true
                bytes = try encode(snapshot())
            }
            guard bytes.count <= Self.maxBytes else { stopped = true; return }
            try replace(bytes)
            let end = clock()
            lastWriteNanoseconds = end >= start ? end - start : 0
            totalWriteNanoseconds = totalWriteNanoseconds.addingReportingOverflow(lastWriteNanoseconds).partialValue
            successfulWrites += 1
            if overflow { stopped = true }
        } catch {
            // Diagnostic faults must not change application control flow. No retry,
            // fallback, deferred flush or file work is permitted after this point.
            stopped = true
        }
    }
}

/// A directory FD anchors all writes. The first install is exclusive; later
/// replacements require the exact inode that this instance previously installed.
/// No existing run file is ever loaded or adopted as this process's evidence.
private final class ReminderProbeAtomicStore {
    private struct Identity: Equatable { let device: dev_t; let inode: ino_t }
    private enum Fault: Error { case unsafe, io }
    private let directory: URL
    private let name: String
    private var directoryFD: Int32 = -1
    private var directoryIdentity: Identity?
    private var fileIdentity: Identity?
    init(directory: URL, name: String) { self.directory = directory; self.name = name }
    deinit { if directoryFD >= 0 { close(directoryFD) } }

    private func identity(_ value: stat) -> Identity {
        Identity(device: value.st_dev, inode: value.st_ino)
    }
    private func currentFile() throws -> Identity? {
        var value = stat()
        let result = fstatat(directoryFD, name, &value, AT_SYMLINK_NOFOLLOW)
        if result != 0 {
            if errno == ENOENT { return nil }
            throw Fault.io
        }
        guard value.st_mode & S_IFMT == S_IFREG, value.st_nlink == 1 else { throw Fault.unsafe }
        return identity(value)
    }
    private func initialize() throws {
        // Reject symlinks in the app-private support directory and witness path.
        for url in [directory.deletingLastPathComponent(), directory] {
            var value = stat()
            if lstat(url.path, &value) == 0 {
                guard value.st_mode & S_IFMT == S_IFDIR else { throw Fault.unsafe }
            } else if errno != ENOENT { throw Fault.io }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        directoryFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directoryFD >= 0 else { throw Fault.io }
        var value = stat()
        guard fstat(directoryFD, &value) == 0 else { throw Fault.io }
        directoryIdentity = identity(value)
        guard try currentFile() == nil else { throw Fault.unsafe }
    }
    func replace(_ data: Data) throws {
        if directoryFD < 0 { try initialize() }
        var directoryStat = stat()
        guard lstat(directory.path, &directoryStat) == 0,
              directoryStat.st_mode & S_IFMT == S_IFDIR,
              identity(directoryStat) == directoryIdentity,
              try currentFile() == fileIdentity else { throw Fault.unsafe }
        let temporary = "." + name + "." + UUID().uuidString + ".tmp"
        let fd = openat(directoryFD, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Fault.io }
        defer { close(fd); unlinkat(directoryFD, temporary, 0) }
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { throw Fault.io }
            // A partial/failed write is terminal, not an I/O retry loop.
            guard Darwin.write(fd, base, raw.count) == raw.count else { throw Fault.io }
        }
        var temporaryStat = stat()
        guard fstat(fd, &temporaryStat) == 0,
              try currentFile() == fileIdentity else { throw Fault.unsafe }
        // RENAME_EXCL prevents racing first installation from replacing old data.
        let flags: UInt32 = fileIdentity == nil ? UInt32(RENAME_EXCL) : 0
        guard renameatx_np(directoryFD, temporary, directoryFD, name, flags) == 0 else { throw Fault.io }
        fileIdentity = identity(temporaryStat)
    }
}
#endif
