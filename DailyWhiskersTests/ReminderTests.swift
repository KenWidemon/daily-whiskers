import Foundation
import Testing
import UserNotifications
@testable import DailyWhiskers

private func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

private final class ReminderTestClock: @unchecked Sendable {
    var date = instant("2027-01-10T12:00:00Z")
    var zone = TimeZone(identifier: "America/New_York")!
}

private final class ReminderMemoryStore: ReminderJournalStore, @unchecked Sendable {
    var value: ReminderJournal?
    var writes = 0
    var failAt: Int?
    var commitThenFailAt: Int?
    var failLoad = false
    var afterSave: ((Int) -> Void)?
    func load() throws -> ReminderJournal? {
        if failLoad { throw ReminderStorageError.unreadable }; return value
    }
    func save(_ journal: ReminderJournal) throws {
        writes += 1
        if failAt == writes { throw ReminderStorageError.verification }
        value = journal
        if commitThenFailAt == writes { throw ReminderStorageError.verification }
        afterSave?(writes)
    }
}

private actor ReminderFakeCenter: ReminderNotificationClient {
    var permission: ReminderAuthorization = .authorized
    var ids: Set<String> = []
    var targets: [String: ReminderTarget] = [:]
    var overrides: [String: ReminderPendingRequest] = [:]
    var shown: Set<String> = []
    var adds: [ReminderTarget] = []
    var removals: [Set<String>] = []
    var permissionRequests = 0
    var requestOutcome: ReminderAuthorization = .authorized
    var inventoryUnknown = false
    var loseAfterAdd = false
    var failAdd = false
    var holdRemoval = false
    var hideWhileDenied = false
    var holdDeliveredRemoval = false
    var revokeOnRemoval = false
    var evictExisting = false
    var revealOnAdd: [String: ReminderTarget] = [:]
    var conflictOnRemoval: ReminderPendingRequest?
    var conflictAfterAdd = false
    var revokeOnAdd = false
    var pendingReads = 0
    var authorizationScript: [ReminderAuthorization] = []
    func scriptAuthorization(_ values: [ReminderAuthorization]) { authorizationScript = values }

    var extraSnapshot: ReminderPendingRequest?
    var extraSnapshotRead = 0
    func revealInOneSnapshot(_ request: ReminderPendingRequest, read: Int) {
        extraSnapshot = request; extraSnapshotRead = read; pendingReads = 0
    }
    func revokeDuringNextAdd() { revokeOnAdd = true }
    func revealAfterNextAdd(_ entries: [String: ReminderTarget]) { revealOnAdd = entries }
    func changeDuringRemoval(_ request: ReminderPendingRequest) { conflictOnRemoval = request }
    func changeAfterAdd() { conflictAfterAdd = true }
    var addInFlight = 0
    var maximumAddsInFlight = 0
    private var holdNextCompletion = false
    private var heldCompletion: CheckedContinuation<Void, Never>?
    private var heldObservers: [CheckedContinuation<Void, Never>] = []
    func holdNextAddCompletion() { holdNextCompletion = true }
    func waitForHeldAdd() async {
        if heldCompletion != nil { return }
        await withCheckedContinuation { heldObservers.append($0) }
    }
    func releaseHeldAdd() { heldCompletion?.resume(); heldCompletion = nil }
    func authorization() -> ReminderAuthorization {
        if !authorizationScript.isEmpty { permission = authorizationScript.removeFirst() }
        return permission
    }
    func requestAlerts() { permissionRequests += 1; permission = requestOutcome }
    func pendingRequests() -> [ReminderPendingRequest]? {
        pendingReads += 1
        if inventoryUnknown { return nil }
        if hideWhileDenied && permission == .denied { return [] }
        var result = ids.map { id in
            if let override = overrides[id] { return override }
            if let target = targets[id] { return ReminderPendingRequest(ReminderRequest.make(id: id, target: target)) }
            return ReminderPendingRequest(UNNotificationRequest(identifier: id, content: UNMutableNotificationContent(), trigger: nil))
        }
        if pendingReads == extraSnapshotRead, let extraSnapshot { result.append(extraSnapshot) }
        return result
    }
    func override(_ request: ReminderPendingRequest) { overrides[request.id] = request }

    func delivered() -> Set<String> { hideWhileDenied && permission == .denied ? [] : shown }
    func add(id: String, target: ReminderTarget) async throws {
        addInFlight += 1; maximumAddsInFlight = max(maximumAddsInFlight, addInFlight)
        await Task.yield()
        defer { addInFlight -= 1 }
        adds.append(target)
        targets[id] = target
        if evictExisting, let first = ids.first { ids.remove(first) }
        if !loseAfterAdd { ids.insert(id) }
        for (revealedID, revealedTarget) in revealOnAdd { ids.insert(revealedID); targets[revealedID] = revealedTarget }
        revealOnAdd = [:]
        if conflictAfterAdd {
            var request = ReminderPendingRequest(ReminderRequest.make(id: id, target: target))
            request.body = "Unexpected changed content"
            overrides[id] = request
        }
        if holdNextCompletion {
            holdNextCompletion = false
            await withCheckedContinuation { continuation in
                heldCompletion = continuation
                for observer in heldObservers { observer.resume() }
                heldObservers.removeAll()
            }
        }
        if revokeOnAdd { permission = .denied; revokeOnAdd = false }
        if failAdd { throw ReminderStorageError.verification }
    }
    func removePending(_ values: Set<String>) {
        removals.append(values)
        if revokeOnRemoval { permission = .denied }
        if !holdRemoval { ids.subtract(values) }
        if let request = conflictOnRemoval { overrides[request.id] = request; conflictOnRemoval = nil }
    }
    func removeDelivered(_ values: Set<String>) { if !holdDeliveredRemoval { shown.subtract(values) } }
    func configure(permission: ReminderAuthorization? = nil, unknown: Bool? = nil,
                   loseAfterAdd: Bool? = nil, failAdd: Bool? = nil, holdRemoval: Bool? = nil, evictExisting: Bool? = nil,
                   requestOutcome: ReminderAuthorization? = nil, hideWhileDenied: Bool? = nil, holdDeliveredRemoval: Bool? = nil, revokeOnRemoval: Bool? = nil) {
        if let revokeOnRemoval { self.revokeOnRemoval = revokeOnRemoval }
        if let hideWhileDenied { self.hideWhileDenied = hideWhileDenied }
        if let holdDeliveredRemoval { self.holdDeliveredRemoval = holdDeliveredRemoval }
        if let permission { self.permission = permission }
        if let unknown { inventoryUnknown = unknown }
        if let loseAfterAdd { self.loseAfterAdd = loseAfterAdd }
        if let failAdd { self.failAdd = failAdd }
        if let holdRemoval { self.holdRemoval = holdRemoval }
        if let evictExisting { self.evictExisting = evictExisting }
        if let requestOutcome { self.requestOutcome = requestOutcome }
    }
    func seed(_ ids: Set<String>, shown: Set<String> = [], targets: [String: ReminderTarget] = [:]) {
        self.ids = ids; self.shown = shown; self.targets.merge(targets) { _, new in new }
    }
}

@Suite("Daily reminder calendar and recovery", .serialized)
struct ReminderTests {
    private func engine(_ store: ReminderMemoryStore, _ center: ReminderFakeCenter,
                        _ clock: ReminderTestClock, budget: Int = 32) -> ReminderScheduler {
        ReminderScheduler(client: center, store: store, now: { clock.date }, zone: { clock.zone }, pendingBudget: budget)
    }

    @Test(arguments: [
        ("2027-01-10", "America/New_York", 9, 0, "2027-01-10T14:00:00Z"),
        ("2027-01-10", "Asia/Kathmandu", 9, 0, "2027-01-10T03:15:00Z"),
        ("2027-11-07", "America/New_York", 1, 30, "2027-11-07T05:30:00Z"),
        ("2027-03-14", "America/New_York", 2, 30, "2027-03-14T07:00:00Z"),
        ("2027-10-03", "Australia/Lord_Howe", 2, 15, "2027-10-02T15:30:00Z"),
        ("2027-04-04", "Australia/Lord_Howe", 1, 45, "2027-04-03T14:45:00Z"),
        ("2018-11-04", "America/Sao_Paulo", 0, 30, "2018-11-04T03:00:00Z"),
        ("2027-11-07", "America/Havana", 0, 30, "2027-11-07T04:30:00Z"),
        ("2011-12-31", "Pacific/Apia", 9, 0, "2011-12-30T19:00:00Z")
    ]) func calendarBoundaries(_ row: (String, String, Int, Int, String)) throws {
        let target = try #require(ReminderCalendar.resolve(day: row.0, zone: TimeZone(identifier: row.1)!,
            time: ReminderTime(hour: row.2, minute: row.3)))
        #expect(target.date == instant(row.4))
        let request = ReminderRequest.make(id: "test", target: target)
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(!trigger.repeats)
        #expect(trigger.dateComponents.timeZone?.secondsFromGMT() == 0)
        #expect(ReminderCalendar.calendar(TimeZone(secondsFromGMT: 0)!).date(from: trigger.dateComponents) == target.date)
        #expect(request.content.sound == nil && request.content.badge == nil)
        #expect(request.content.title == "Daily Whiskers")
        #expect(request.content.body == "Your daily whisker of encouragement is ready.")
    }

    @Test func fourteenCivilDatesNoBackfillOrCatchup() {
        let zone = TimeZone(identifier: "America/New_York")!
        let before = ReminderCalendar.queue(now: instant("2027-01-10T12:00:00Z"), zone: zone, time: ReminderTime())
        #expect(before.count == 14 && before.first?.day == "2027-01-10" && before.last?.day == "2027-01-23")
        let after = ReminderCalendar.queue(now: instant("2027-01-10T14:00:00Z"), zone: zone, time: ReminderTime())
        #expect(after.count == 13 && after.first?.day == "2027-01-11" && after.last?.day == "2027-01-23")
        let apia = TimeZone(identifier: "Pacific/Apia")!
        #expect(ReminderCalendar.resolve(day: "2011-12-30", zone: apia, time: ReminderTime()) == nil)
        let skipped = ReminderCalendar.queue(now: instant("2011-12-29T10:00:00Z"), zone: apia, time: ReminderTime())
        #expect(skipped.count == 13 && !skipped.contains { $0.day == "2011-12-30" })
        #expect(Set(skipped.map(\.date)).count == skipped.count)
        let fold = ReminderCalendar.queue(now: instant("2027-11-07T05:45:00Z"), zone: zone, time: ReminderTime(hour: 1, minute: 30))
        #expect(fold.count == 13 && fold.first?.day == "2027-11-08")
        #expect(ReminderCalendar.resolve(day: "invalid", zone: zone, time: ReminderTime()) == nil)
        #expect(ReminderCalendar.resolve(day: "2027-02-30", zone: zone, time: ReminderTime()) == nil)
        #expect(ReminderCalendar.resolve(day: "2027-01-10", zone: zone, time: ReminderTime(hour: 24)) == nil)
    }

    @Test func freshInstallSaveTimeDoesNotEnableOrPromptAndExplicitEnableIsIdempotent() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        await center.configure(permission: .notDetermined)
        let scheduler = engine(store, center, clock)
        let first = await scheduler.submit(.refresh)
        #expect(!first.enabled && first.time == ReminderTime() && first.queued == 0)
        _ = await scheduler.submit(.time(ReminderTime(hour: 10, minute: 15)))
        #expect(await center.permissionRequests == 0)
        #expect(await center.adds.isEmpty)
        let enabled = await scheduler.submit(.enable(true))
        #expect(enabled.enabled && enabled.queued == 14)
        #expect(await center.permissionRequests == 1)
        _ = await scheduler.submit(.refresh)
        _ = await scheduler.submit(.enable(true))
        #expect(await center.adds.count == 14)
        #expect(await center.permissionRequests == 1)
        let relaunched = await engine(store, center, clock).submit(.refresh)
        #expect(relaunched.queued == 14 && relaunched.time.hour == 10)
        #expect(await center.adds.count == 14)
    }

    @Test func revocationPreservesOriginalsAndDisableClearsOnlyOwned() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        await center.configure(permission: .denied)
        let denied = await scheduler.submit(.refresh)
        #expect(denied.enabled && denied.authorization == .denied && denied.queued == 0)
        #expect(await center.permissionRequests == 0)
        await center.configure(permission: .authorized)
        #expect(await scheduler.submit(.refresh).queued == 14)
        #expect(await center.adds.count == 14)
        #expect(await center.removals.isEmpty)
        #expect(store.value?.exposures.isEmpty == true)
        let own = await center.ids
        await center.seed(own.union(["unrelated"]), shown: [ReminderRequest.prefix + "old", "unrelated-delivered"])
        _ = await scheduler.submit(.enable(false))
        #expect(await center.ids == ["unrelated"])
        #expect(await center.shown == ["unrelated-delivered"])
        await center.configure(permission: .denied)
        _ = await scheduler.submit(.refresh)
        await center.configure(permission: .authorized)
        let disabled = await scheduler.submit(.refresh)
        #expect(!disabled.enabled && disabled.queued == 0)
        #expect(store.value?.time == ReminderTime())
    }

    @Test func elapsedAndClearedNotificationsKeepHistoryOnEditReenableAndReopen() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        clock.date = instant("2027-01-10T15:00:00Z")
        let remaining = await center.ids.subtracting([store.value!.entries[0].id])
        await center.seed(remaining) // User-cleared/missing delivery proves nothing.
        _ = await scheduler.submit(.time(ReminderTime(hour: 11)))
        #expect(store.value?.exposures.contains { $0.day == "2027-01-10" } == true)
        #expect(store.value?.entries.contains { $0.target.day == "2027-01-10" } == false)
        _ = await scheduler.submit(.enable(false)); _ = await scheduler.submit(.enable(true))
        #expect(store.value?.entries.contains { $0.target.day == "2027-01-10" } == false)
        _ = await engine(store, center, clock).submit(.refresh)
        #expect(store.value?.entries.contains { $0.target.day == "2027-01-10" } == false)
    }

    @Test func unknownCapacityStillCancelsObsoleteTravelRequest() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        clock.date = instant("2027-01-09T23:00:00Z"); clock.zone = TimeZone(identifier: "Asia/Tokyo")!
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        let oldIDs = await center.ids
        clock.date = instant("2027-01-10T23:00:00Z"); clock.zone = TimeZone(identifier: "America/Los_Angeles")!
        await center.configure(unknown: true)
        let result = await scheduler.submit(.refresh)
        #expect(result.queued == 0)
        #expect(await center.removals.contains(oldIDs))
        #expect(await center.adds.count == 14)
        await center.configure(unknown: false)
        _ = await scheduler.submit(.refresh)
        #expect(store.value?.entries.contains { $0.target.day == "2027-01-10" } == false)
        #expect(await center.ids.isEmpty) // Uncertain future reservations suppress, not replay.
    }

    @Test func unopenedDateLineExceptionIsExplicitAndReopeningSuppressesExperiencedDate() async {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!, la = TimeZone(identifier: "America/Los_Angeles")!
        let first = ReminderCalendar.resolve(day: "2027-01-10", zone: tokyo, time: ReminderTime())!
        let second = ReminderCalendar.resolve(day: "2027-01-11", zone: tokyo, time: ReminderTime())!
        #expect(first.day != second.day)
        #expect(ReminderCalendar.day(first.date, zone: tokyo) == ReminderCalendar.day(second.date, zone: la))
        var journal = ReminderJournal()
        journal.remember(ReminderEntry(id: "x", target: first, phase: .pending), through: instant("2027-01-10T23:00:00Z"))
        let later = ReminderCalendar.resolve(day: "2027-01-10", zone: la, time: ReminderTime(hour: 23))!
        #expect(journal.blocks(later, now: instant("2027-01-10T23:00:00Z")))
    }

    @Test func queueBudgetReservesOtherFeaturesAndUnknownInventoryBlocksAdd() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        await center.seed(["other1", "other2"])
        let scheduler = engine(store, center, clock, budget: 4)
        #expect(await scheduler.submit(.enable(true)).queued == 2)
        #expect(await center.ids.count == 4)
        let secondStore = ReminderMemoryStore(); secondStore.value = ReminderJournal()
        let other = ReminderFakeCenter(); await other.configure(unknown: true)
        #expect(await engine(secondStore, other, clock).submit(.enable(true)).queued == 0)
        #expect(await other.adds.isEmpty)
    }

    @Test(arguments: [ReminderEntry.Phase.intent, .cancelling])
    func interruptedOperationsAreNeverReplayed(_ phase: ReminderEntry.Phase) async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let target = ReminderCalendar.queue(now: clock.date, zone: clock.zone, time: ReminderTime())[0]
        let entry = ReminderEntry(id: ReminderRequest.prefix + "interrupted", target: target, phase: phase)
        var journal = ReminderJournal(); journal.enabled = true; journal.entries = [entry]; store.value = journal
        await center.seed([entry.id], targets: [entry.id: entry.target])
        _ = await engine(store, center, clock).submit(.refresh)
        #expect(store.value?.exposures.contains { $0.day == target.day } == true)
        #expect(await !center.adds.contains { $0.day == target.day })
        #expect(await center.adds.count == 13)
    }

    @Test func unresolvedCancellationStopsAddsUntilAbsenceAndKeepsUncertainty() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        await center.configure(holdRemoval: true)
        let result = await scheduler.submit(.time(ReminderTime(hour: 10)))
        #expect(result.message != nil && result.queued == 0)
        #expect(await center.adds.count == 14)
        await center.configure(holdRemoval: false)
        _ = await scheduler.submit(.refresh)
        #expect(await center.adds.count == 14)
        #expect(store.value?.exposures.count == 14)
    }

    @Test(arguments: [true, false]) func addUncertaintyStopsBatch(_ throwing: Bool) async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        await center.configure(loseAfterAdd: !throwing, failAdd: throwing)
        let scheduler = engine(store, center, clock)
        let result = await scheduler.submit(.enable(true))
        #expect(result.message != nil)
        #expect(await center.adds.count == 1)
        #expect(store.value?.entries.first?.phase == .cancelling)
        #expect(store.value?.exposures.count == 1)
    }

    @Test func failedIntentWritePreventsAddAndFailedAcknowledgementIsRecoveredConservatively() async {
        for failAt in [5, 6] {
            let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
            store.failAt = failAt
            let scheduler = engine(store, center, clock)
            let result = await scheduler.submit(.enable(true))
            #expect(result.storageBlocked)
            #expect(await center.adds.count == (failAt == 5 ? 0 : 1))
            _ = await scheduler.submit(.refresh)
            #expect(await center.adds.count == (failAt == 5 ? 0 : 1))
            store.failAt = nil
            _ = await engine(store, center, clock).submit(.refresh)
            if failAt == 6 { #expect(store.value?.exposures.count == 1) }
        }
    }

    @Test func corruptJournalAndClockRollbackFailClosed() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        store.failLoad = true
        #expect(await engine(store, center, clock).submit(.enable(true)).storageBlocked)
        #expect(await center.adds.isEmpty)
        store.failLoad = false
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        clock.date = clock.date.addingTimeInterval(-3600)
        #expect(await scheduler.submit(.refresh).queued == 0)
        #expect(await center.adds.count == 14)
    }

    @Test func exhaustedQueueRefillsOnlyFutureDatesAndSerializedCallsDoNotDuplicate() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        clock.date = instant("2027-01-28T12:00:00Z")
        await center.seed([])
        let result = await scheduler.submit(.refresh)
        #expect(result.queued == 13) // Unobserved possible presentations conservatively cover today.
        #expect(store.value?.entries.first?.target.day == "2027-01-29")
        let count = await center.adds.count
        await withTaskGroup(of: ReminderStatus.self) { group in
            for _ in 0..<10 { group.addTask { await scheduler.submit(.refresh) } }
            for await _ in group { }
        }
        #expect(await center.adds.count == count)
        #expect(await center.maximumAddsInFlight == 1)
    }

    @Test func fileJournalRoundTripMissingAndCorruptStateAreNotFreshInstalls() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileReminderJournalStore(directory: directory)
        #expect(try store.load() == nil)
        var value = ReminderJournal(); value.enabled = true; value.time = ReminderTime(hour: 17, minute: 20)
        try store.save(value)
        #expect(try FileReminderJournalStore(directory: directory).load() == value)
        try Data("corrupt".utf8).write(to: directory.appendingPathComponent("journal.json"))
        #expect(throws: Error.self) { try store.load() }
        try FileManager.default.removeItem(at: directory.appendingPathComponent("journal.json"))
        #expect(throws: Error.self) { try store.load() }
    }

    @Test(arguments: [30.0, 60.0, 61.0]) func cancellationNearDeadlineKeepsReservation(_ margin: Double) async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        clock.date = instant("2027-01-10T14:00:00Z").addingTimeInterval(-margin)
        _ = await scheduler.submit(.time(ReminderTime(hour: 10)))
        #expect(store.value?.entries.contains { $0.target.day == "2027-01-10" } == (margin > 60))
        #expect(store.value?.exposures.contains { $0.day == "2027-01-10" } == (margin <= 60))
    }

    @Test(arguments: [false, true])
    func hiddenPermissionRequestsResumeOnlyEnabledIntent(_ disable: Bool) async throws {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        let original = try #require(store.value).entries
        await center.seed(await center.ids.union(["unrelated"]), shown: ["unrelated-shown"])
        await center.configure(permission: .denied, holdRemoval: true, hideWhileDenied: true)
        for _ in 0..<3 { #expect(await scheduler.submit(.refresh).queued == 0) }
        #expect(store.value?.entries == original)
        #expect(store.value?.exposures.isEmpty == true)
        #expect(store.value?.permissionSuspended == nil)
        #expect(await center.removals.isEmpty)
        if disable { _ = await scheduler.submit(.enable(false)) }
        await center.configure(permission: .authorized, holdRemoval: false)
        let resumed = await engine(store, center, clock).submit(.refresh)
        #expect(!resumed.storageBlocked && resumed.enabled == !disable)
        #expect(resumed.queued == (disable ? 0 : 14))
        #expect((store.value?.retired?.count ?? 0) == (disable ? 14 : 0))
        #expect(await center.adds.count == 14)
        #expect(await center.ids.contains("unrelated"))
        #expect(await center.shown == ["unrelated-shown"])
        #expect(await center.permissionRequests == 0)
        if disable {
            // A later return of already-removed IDs is known, not a quarantine.
            await center.seed(await center.ids.union(Set(original.map(\.id))))
            let returned = await engine(store, center, clock).submit(.refresh)
            #expect(!returned.storageBlocked && returned.queued == 0)
            #expect(store.value?.exposures.count == 14)
            #expect(await center.ids == ["unrelated"])
        } else {
            #expect(store.value?.entries == original)
            #expect(await center.removals.isEmpty)
        }
    }

    @Test(arguments: [30.0, 60.0, 61.0, -1.0])
    func hiddenPermissionRegrantHonorsDeadlineAndClock(_ margin: Double) async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        await center.configure(permission: .denied, holdRemoval: true, hideWhileDenied: true)
        _ = await scheduler.submit(.refresh)
        clock.date = margin < 0 ? clock.date.addingTimeInterval(-1) : instant("2027-01-10T14:00:00Z").addingTimeInterval(-margin)
        await center.configure(permission: .authorized, holdRemoval: false)
        let status = await engine(store, center, clock).submit(.refresh)
        #expect(!status.storageBlocked)
        #expect(status.queued == (margin < 0 ? 0 : 14))
        #expect(store.value?.exposures.contains { $0.day == "2027-01-10" } == (margin < 0))
    }

    @Test(arguments: [false, true])
    func interruptedRegrantNeverReleasesUncertainReservations(_ committed: Bool) async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        await center.configure(permission: .denied, holdRemoval: true, hideWhileDenied: true)
        _ = await scheduler.submit(.refresh)
        await center.configure(permission: .authorized, holdRemoval: false)
        // Legacy v2 suspension already requested cancellation. Never treat it
        // as an untouched request when migrating to the keep-original path.
        store.value?.permissionSuspended = true
        let resumedScheduler = engine(store, center, clock)
        // Fail the post-removal persistence, after cancellation intent is durable.
        if committed { store.commitThenFailAt = store.writes + 2 } else { store.failAt = store.writes + 2 }
        #expect(await resumedScheduler.submit(.refresh).storageBlocked)
        store.failAt = nil; store.commitThenFailAt = nil
        let resumed = await engine(store, center, clock).submit(.refresh)
        #expect(!resumed.storageBlocked)
        #expect(resumed.queued == (committed ? 14 : 0))
        #expect(store.value?.requiresRecovery == false)
    }

    @Test func quarantineOffSurvivesDeferredCleanupAndRelaunch() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        var state = ReminderJournal(); state.version = 1; state.enabled = true; state.requiresRecovery = true
        state.exposures = [ReminderExposure(day: "2027-01-10", from: clock.date, through: clock.date)]
        store.value = state
        await center.seed([], shown: [ReminderRequest.prefix + "old", "unrelated"])
        await center.configure(holdDeliveredRemoval: true)
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.refresh)
        let off = await scheduler.submit(.enable(false))
        #expect(off.storageBlocked && !off.enabled)
        #expect(store.value?.version == 3)
        #expect(store.value?.requiresRecovery == true && store.value?.exposures == state.exposures)
        await center.configure(holdDeliveredRemoval: false)
        let reopened = await engine(store, center, clock).submit(.refresh)
        #expect(reopened.storageBlocked && !reopened.enabled)
        #expect(await center.shown == ["unrelated"])
        #expect(await center.adds.isEmpty)
    }

    @Test func repeatedPermissionCyclesResumeWithoutDuplicatingDates() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        _ = await engine(store, center, clock).submit(.enable(true))
        for _ in 1...3 {
            await center.configure(permission: .denied, holdRemoval: true, hideWhileDenied: true)
            _ = await engine(store, center, clock).submit(.refresh)
            await center.configure(permission: .authorized, holdRemoval: false)
            let status = await engine(store, center, clock).submit(.refresh)
            #expect(!status.storageBlocked && status.queued == 14)
            #expect(store.value?.entries.count == 14 && store.value?.retired == nil)
            #expect(await center.adds.count == 14)
            #expect(await center.removals.isEmpty)
            #expect(await center.ids.count == 14)
        }
    }

    @Test func absentAfterRegrantSkipsUncertainHorizonButRefillsNewDates() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        await center.configure(permission: .denied, hideWhileDenied: true)
        _ = await scheduler.submit(.refresh)
        await center.seed([]) // The OS truly loses requests, not our cancellation.
        await center.configure(permission: .authorized)
        let absent = await scheduler.submit(.refresh)
        #expect(!absent.storageBlocked && absent.enabled && absent.queued == 0)
        #expect(store.value?.exposures.count == 14)
        clock.date = clock.date.addingTimeInterval(86400)
        let refill = await engine(store, center, clock).submit(.refresh)
        #expect(!refill.storageBlocked && refill.queued == 1)
        #expect(store.value?.entries.first?.target.day == "2027-01-24")
        #expect(store.value?.exposures.count == 14)
    }

    @Test func permissionRevokedDuringRemovalPreventsFurtherAdds() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        clock.date = clock.date.addingTimeInterval(86400)
        await center.configure(revokeOnRemoval: true)
        let status = await scheduler.submit(.time(ReminderTime(hour: 10)))
        #expect(status.authorization == .denied && status.queued == 0)
        #expect(await center.adds.count == 14)
    }

    @Test func fullRequestProjectionSurvivesNativeArchiveAndNormalizesUTCAliases() throws {
        let target = try #require(ReminderCalendar.resolve(day: "2027-01-10", zone: TimeZone(identifier: "America/New_York")!, time: ReminderTime()))
        let request = ReminderRequest.make(id: ReminderRequest.prefix + "native", target: target)
        let archived = try NSKeyedArchiver.archivedData(withRootObject: request, requiringSecureCoding: true)
        let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: UNNotificationRequest.self, from: archived)
        let restored = try #require(decoded)
        #expect(ReminderRequest.matches(ReminderPendingRequest(restored), id: request.identifier, target: target))
        for name in ["GMT", "UTC", "Etc/UTC", "Etc/GMT"] {
            var projected = ReminderPendingRequest(request)
            let zone = try #require(TimeZone(identifier: name))
            projected.calendarComponents?.timeZone = zone
            projected.calendarComponents?.calendar?.timeZone = zone
            #expect(ReminderRequest.matches(projected, id: request.identifier, target: target))
        }
    }

    @Test(arguments: Array(0..<24)) func fullRequestProjectionRejectsConflictingFields(_ field: Int) throws {
        let target = try #require(ReminderCalendar.resolve(day: "2027-01-10", zone: TimeZone(secondsFromGMT: 0)!, time: ReminderTime()))
        let id = ReminderRequest.prefix + "projection"
        var request = ReminderPendingRequest(ReminderRequest.make(id: id, target: target))
        switch field {
        case 0: request.id += "changed"
        case 1: request.calendarComponents?.day = 11
        case 2: request.calendarComponents?.hour = 10
        case 3: request.calendarComponents?.timeZone = TimeZone(identifier: "America/New_York")
        case 4: request.calendarComponents?.calendar = Calendar(identifier: .buddhist)
        case 5: request.calendarComponents = nil
        case 6: request.repeats = true
        case 7: request.title += "changed"
        case 8: request.body += "changed"
        case 9: request.route = "other"
        case 10: request.unexpectedUserInfo = true
        case 11: request.hasSound = true
        case 12: request.badge = 0
        case 13: request.category = "unexpected"
        case 14: request.thread = "unexpected"
        case 15: request.targetContent = "unexpected"
        case 16: request.launchImage = "unexpected"
        case 17: request.attachmentCount = 1
        case 18: request.interruptionLevel += 1
        case 19: request.relevanceScore = 0.5
        case 20: request.subtitle = "unexpected"
        case 21: request.calendarComponents?.weekday = 1
        case 22: request.calendarComponents?.calendar = nil
        default: request.filterCriteria = "unexpected"
        }
        #expect(!ReminderRequest.matches(request, id: id, target: target))
    }

    @Test(arguments: Array(0..<8)) func nativeProjectionRejectsNoncanonicalRequests(_ mutation: Int) throws {
        let target = try #require(ReminderCalendar.resolve(day: "2027-01-10", zone: TimeZone(secondsFromGMT: 0)!, time: ReminderTime()))
        let id = ReminderRequest.prefix + "native-conflict"
        let original = ReminderRequest.make(id: id, target: target)
        let content = try #require(original.content.mutableCopy() as? UNMutableNotificationContent)
        var trigger = original.trigger
        switch mutation {
        case 0: content.userInfo = ["dw004": "today", "unexpected": "extra"]
        case 1: content.userInfo = ["dw004": 7]
        case 2: content.sound = .default
        case 3: content.badge = 0
        case 4: trigger = UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false)
        case 5:
            let components = try #require((original.trigger as? UNCalendarNotificationTrigger)?.dateComponents)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        case 6: content.body = "Changed body"
        default: content.filterCriteria = "unexpected"
        }
        let modified = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        #expect(!ReminderRequest.matches(ReminderPendingRequest(modified), id: id, target: target))
    }

    @Test(arguments: [false, true]) func deniedPersistenceFailureNeverAddsOrResetsHistory(_ committed: Bool) async throws {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        let original = try #require(store.value?.entries)
        await center.configure(permission: .denied, hideWhileDenied: true)
        if committed { store.commitThenFailAt = store.writes + 1 } else { store.failAt = store.writes + 1 }
        let failure = await scheduler.submit(.refresh)
        #expect(failure.storageBlocked && failure.queued == 0)
        #expect(store.value?.entries == original)
        store.failAt = nil; store.commitThenFailAt = nil
        #expect(await scheduler.submit(.refresh).storageBlocked)
        await center.configure(permission: .authorized)
        let recovered = await engine(store, center, clock).submit(.refresh)
        #expect(!recovered.storageBlocked && recovered.queued == 14)
        #expect(store.value?.exposures.isEmpty == true)
        #expect(await center.adds.count == 14)
        #expect(store.value?.entries == original) // No new cancellation after failed bookkeeping.
    }

    @Test(arguments: [false, true]) func conflictingRequestQuarantinesOnRegrantOrAfterAdd(_ afterAdd: Bool) async throws {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock)
        if afterAdd { await center.changeAfterAdd() }
        _ = await scheduler.submit(.enable(true))
        if !afterAdd {
            await center.configure(permission: .denied, hideWhileDenied: true)
            _ = await scheduler.submit(.refresh)
            let entry = try #require(store.value?.entries.first)
            var conflict = ReminderPendingRequest(ReminderRequest.make(id: entry.id, target: entry.target))
            conflict.repeats = true
            await center.override(conflict)
            await center.configure(permission: .authorized)
        }
        let result = await scheduler.submit(.refresh)
        #expect(result.storageBlocked && result.queued == 0)
        #expect(store.value?.requiresRecovery == true)
        #expect(await center.adds.count == (afterAdd ? 1 : 14))
    }

    @Test func cancellationReadbackDoesNotConfirmChangedSurvivor() async throws {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock, budget: 2)
        _ = await scheduler.submit(.enable(true))
        let survivor = try #require(store.value?.entries.last)
        var conflict = ReminderPendingRequest(ReminderRequest.make(id: survivor.id, target: survivor.target))
        conflict.body = "changed during cancellation"
        await center.changeDuringRemoval(conflict)
        clock.date = instant("2027-01-10T15:00:00Z")
        let status = await scheduler.submit(.refresh)
        #expect(status.storageBlocked && status.queued == 0)
        #expect(await center.adds.count == 2)
    }

    @Test func retiredIDReturningOnlyAfterAddIsKnownAndStopsAffectedCoverage() async throws {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let oldTarget = try #require(ReminderCalendar.resolve(day: "2027-01-09", zone: clock.zone, time: ReminderTime()))
        let retired = ReminderEntry(id: ReminderRequest.prefix + "retired", target: oldTarget, phase: .cancelling)
        var journal = ReminderJournal(); journal.retired = [retired]; store.value = journal
        await center.revealAfterNextAdd([retired.id: oldTarget])
        let status = await engine(store, center, clock).submit(.enable(true))
        #expect(!status.storageBlocked && status.queued == 0)
        #expect(store.value?.requiresRecovery == false)
        #expect(store.value?.exposures.contains { $0.day == oldTarget.day } == true)
        #expect(await center.ids.isEmpty)
        #expect(await center.adds.count == 1)
    }

    @Test(arguments: [2, 3])
    func retiredReturnDuringCancellationRemovesItAndBlockedReplacement(_ read: Int) async throws {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        clock.date = instant("2027-01-10T15:00:00Z")
        let obsoleteTarget = try #require(ReminderCalendar.resolve(day: "2027-01-10", zone: clock.zone, time: ReminderTime()))
        let futureTarget = try #require(ReminderCalendar.resolve(day: "2027-01-11", zone: clock.zone, time: ReminderTime()))
        let obsolete = ReminderEntry(id: ReminderRequest.prefix + "obsolete", target: obsoleteTarget, phase: .pending)
        let replacement = ReminderEntry(id: ReminderRequest.prefix + "replacement", target: futureTarget, phase: .pending)
        let retired = ReminderEntry(id: ReminderRequest.prefix + "retired", target: futureTarget, phase: .cancelling)
        var journal = ReminderJournal(); journal.enabled = true; journal.entries = [obsolete, replacement]; journal.retired = [retired]
        store.value = journal
        await center.seed([obsolete.id, replacement.id], targets: [obsolete.id: obsoleteTarget, replacement.id: futureTarget])
        await center.revealInOneSnapshot(ReminderPendingRequest(ReminderRequest.make(id: retired.id, target: futureTarget)), read: read)
        let status = await engine(store, center, clock).submit(.refresh)
        #expect(!status.storageBlocked && status.queued == 0)
        #expect(store.value?.requiresRecovery == false)
        #expect(store.value?.exposures.contains { $0.day == futureTarget.day } == true)
        #expect(await center.removals.contains { $0.contains(retired.id) && $0.contains(replacement.id) })
        #expect(await center.ids.isEmpty)
        #expect(await center.adds.isEmpty)
    }

    @Test func positiveDeliveryEvidenceBlocksFuturePendingCopyEvenAfterClearing() async throws {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        let first = try #require(store.value?.entries.first)
        await center.seed(await center.ids, shown: [first.id])
        let observed = await scheduler.submit(.refresh)
        #expect(!observed.storageBlocked && observed.queued == 13)
        #expect(store.value?.exposures.contains { $0.day == first.target.day } == true)
        await center.seed(await center.ids) // Clearing is not negative delivery evidence.
        _ = await engine(store, center, clock).submit(.refresh)
        #expect(await center.adds.count == 14)
    }

    @Test func unknownInventoryRetainsButNeverConfirmsOrReaddsOriginals() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        let original = store.value?.entries
        await center.configure(unknown: true)
        let unknown = await scheduler.submit(.refresh)
        #expect(!unknown.storageBlocked && unknown.queued == 0)
        #expect(store.value?.entries == original)
        #expect(await center.removals.isEmpty)
        #expect(await center.adds.count == 14)
        await center.configure(unknown: false)
        #expect(await scheduler.submit(.refresh).queued == 14)
    }

    @Test(arguments: ["time", "zone", "off", "exposure", "elapsed", "rollback"])
    func denialNeverPreservesIneligibleOriginals(_ change: String) async throws {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        let original = try #require(store.value?.entries)
        await center.configure(permission: .denied, hideWhileDenied: true)
        switch change {
        case "time": _ = await scheduler.submit(.time(ReminderTime(hour: 10)))
        case "zone": clock.zone = TimeZone(identifier: "Asia/Tokyo")!; _ = await scheduler.submit(.refresh)
        case "off": _ = await scheduler.submit(.enable(false))
        case "exposure":
            store.value?.remember(original[0], through: clock.date)
            _ = await engine(store, center, clock).submit(.refresh)
        case "elapsed": clock.date = instant("2027-01-10T15:00:00Z"); _ = await scheduler.submit(.refresh)
        default: clock.date = clock.date.addingTimeInterval(-1); _ = await scheduler.submit(.refresh)
        }
        #expect(await center.removals.contains { $0.contains(original[0].id) })
        #expect(await center.adds.count == 14)
        #expect(store.value?.exposures.contains { $0.day == original[0].target.day } == true)
    }

    @Test func permissionRevokedDuringAddStopsWithoutReplacingOrCancellingOriginal() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        await center.revokeDuringNextAdd()
        await center.configure(hideWhileDenied: true)
        let scheduler = engine(store, center, clock)
        let status = await scheduler.submit(.enable(true))
        #expect(status.authorization == .denied && status.queued == 0)
        #expect(await center.adds.count == 1)
        #expect(await center.removals.isEmpty)
        #expect(store.value?.exposures.isEmpty == true)
        let originalID = store.value?.entries.first?.id
        await center.configure(permission: .authorized)
        let resumed = await scheduler.submit(.refresh)
        #expect(resumed.queued == 14)
        #expect(store.value?.entries.first?.id == originalID)
        #expect(await center.adds.count == 14)
    }

    @Test func legacyJournalUpgradesBeforeNotificationEffects() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        var legacy = ReminderJournal(); legacy.version = 1; store.value = legacy
        let status = await engine(store, center, clock).submit(.enable(true))
        #expect(status.queued == 14 && store.value?.version == 3)
    }

    @Test func legacyJournalDecodesWithoutNewProvenanceFields() throws {
        var original = ReminderJournal(); original.version = 1
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReminderJournal.self, from: data)
        #expect(decoded.retired == nil && decoded.permissionSuspended == nil)
        try decoded.validate()
        var corrupt = decoded
        let target = try #require(ReminderCalendar.resolve(day: "2027-01-10", zone: TimeZone(secondsFromGMT: 0)!, time: ReminderTime()))
        let entry = ReminderEntry(id: ReminderRequest.prefix + "duplicate", target: target, phase: .pending)
        corrupt.entries = [entry]; corrupt.retired = [entry]
        #expect(throws: Error.self) { try corrupt.validate() }
    }

    @Test func orphanRequestsQuarantinePersistsAfterRemovalAndRelaunch() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        await center.seed([ReminderRequest.prefix + "orphan"])
        let first = await engine(store, center, clock).submit(.refresh)
        #expect(first.storageBlocked && store.value?.requiresRecovery == true)
        #expect(await center.ids.isEmpty)
        let second = await engine(store, center, clock).submit(.enable(true))
        #expect(second.storageBlocked)
        #expect(await center.adds.isEmpty)
    }

    @Test func journalRejectsUnsupportedVersionAndWrongDateIdentity() {
        var value = ReminderJournal(); value.version = 4
        #expect(throws: Error.self) { try value.validate() }
        value.version = 1
        value.entries = [ReminderEntry(id: ReminderRequest.prefix + "bad", target: ReminderTarget(day: "2027-01-11", zone: "UTC", date: instant("2027-01-10T09:00:00Z")), phase: .pending)]
        #expect(throws: Error.self) { try value.validate() }
    }

    @Test func disablingClearsDeliveredEvenWhenPendingRemovalIsUncertain() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        await center.seed(await center.ids, shown: [ReminderRequest.prefix + "shown", "other"])
        await center.configure(unknown: true, holdRemoval: true)
        _ = await scheduler.submit(.enable(false))
        #expect(await center.shown == ["other"])
        #expect(store.value?.enabled == false)
        #expect(store.value?.entries.allSatisfy { $0.phase == .cancelling } == true)
    }

    @Test func retentionLossStopsTheBatchWithoutReplacingMissingRequests() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        await center.configure(evictExisting: true)
        let status = await engine(store, center, clock).submit(.enable(true))
        #expect(status.message != nil)
        #expect(await center.adds.count == 2)
        #expect(store.value?.entries.allSatisfy { $0.phase == .cancelling } == true)
        #expect(store.value?.exposures.count == 2)
    }

    @Test func deniedOptInDoesNotPromptAgainOnReopenOrRepeatedEnable() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        await center.configure(permission: .notDetermined, requestOutcome: .denied)
        let scheduler = engine(store, center, clock)
        let denied = await scheduler.submit(.enable(true))
        #expect(denied.authorization == .denied && denied.enabled && denied.queued == 0)
        _ = await scheduler.submit(.refresh); _ = await scheduler.submit(.enable(true))
        _ = await engine(store, center, clock).submit(.refresh)
        #expect(await center.permissionRequests == 1)
        #expect(await center.adds.isEmpty)
    }

    @Test func deadlineCrossedDuringIntentPersistenceNeverAddsPastTarget() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        store.afterSave = { write in if write == 5 { clock.date = instant("2027-01-10T14:00:01Z") } }
        let result = await engine(store, center, clock).submit(.enable(true))
        #expect(result.message != nil && result.queued == 0)
        #expect(await center.adds.isEmpty)
        #expect(store.value?.exposures.first?.day == "2027-01-10")
    }

    @Test func quarantinedAndInvalidHistoryDoNotPromiseRecoveryByReopening() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        await center.seed([ReminderRequest.prefix + "orphan"])
        let scheduler = engine(store, center, clock)
        let first = await scheduler.submit(.refresh)
        #expect(first.message?.contains("Reopening won't repair it") == true)
        #expect(first.message?.contains("Contact Support") == true)
        let preserved = store.value
        let sameProcess = await scheduler.submit(.refresh)
        let relaunched = await engine(store, center, clock).submit(.refresh)
        #expect(sameProcess.message == first.message && relaunched.message == first.message)
        #expect(store.value == preserved && store.value?.requiresRecovery == true)
        #expect(await center.adds.isEmpty)
        let invalid = ReminderMemoryStore(); invalid.failLoad = true
        #expect(await engine(invalid, center, clock).submit(.refresh).message == first.message)
    }

    @Test func retryableStorageFailureRequiresAProcessRestartAndPreservesHistory() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        store.failAt = 4
        let scheduler = engine(store, center, clock)
        let failed = await scheduler.submit(.enable(true))
        #expect(failed.storageBlocked && failed.message?.contains("Close the app completely") == true)
        #expect(failed.message?.contains("Reopening won't repair it") == false)
        let preserved = store.value
        store.failAt = nil
        let sameProcess = await scheduler.submit(.refresh)
        #expect(sameProcess.storageBlocked && sameProcess.message == failed.message)
        #expect(store.value == preserved)
        let relaunched = await engine(store, center, clock).submit(.refresh)
        #expect(!relaunched.storageBlocked && relaunched.enabled && relaunched.queued == 14)
    }

    @Test(arguments: [5, 6]) func committedWriteWithThrownResultNeverReplaysTheUncertainDate(_ write: Int) async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        store.commitThenFailAt = write
        let failed = await engine(store, center, clock).submit(.enable(true))
        #expect(failed.storageBlocked)
        #expect(store.value?.entries.first?.phase == (write == 5 ? .intent : .pending))
        #expect(await center.adds.count == (write == 5 ? 0 : 1))
        store.commitThenFailAt = nil
        let recovered = await engine(store, center, clock).submit(.refresh)
        #expect(!recovered.storageBlocked && recovered.queued == 13)
        #expect(store.value?.exposures.contains { $0.day == "2027-01-10" } == true)
        #expect(store.value?.entries.contains { $0.target.day == "2027-01-10" } == false)
        #expect(await center.adds.filter { $0.day == "2027-01-10" }.count == (write == 5 ? 0 : 1))
    }

    @Test func disableAndTimeChangeWaitForHeldAddCompletionWithoutInterleaving() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock, budget: 2)
        await center.holdNextAddCompletion()
        let enabling = await scheduler.enqueue(.enable(true))
        await center.waitForHeldAdd()
        let disabling = await scheduler.enqueue(.enable(false))
        let editing = await scheduler.enqueue(.time(ReminderTime(hour: 10, minute: 15)))
        // These commands are registered in order while add completion is held.
        #expect(store.value?.enabled == true && store.value?.time == ReminderTime())
        #expect(store.value?.entries.first?.phase == .intent)
        #expect(await center.adds.count == 1)
        #expect(await center.removals.isEmpty)
        await center.releaseHeldAdd()
        #expect(await enabling.value.queued == 2)
        #expect(await disabling.value.enabled == false)
        let final = await editing.value
        #expect(!final.enabled && final.time == ReminderTime(hour: 10, minute: 15) && final.queued == 0)
        #expect(await center.ids.isEmpty)
        #expect(await center.adds.count == 2)
        #expect(await center.maximumAddsInFlight == 1)
    }
}


extension ReminderTests {
    @Test func cleanupPendingSurvivesDeniedRefreshRestartAndRegrant() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        let originals = store.value!.entries
        await center.configure(permission: .denied, holdRemoval: true, hideWhileDenied: true, holdDeliveredRemoval: true)
        let off = await scheduler.submit(.enable(false))
        #expect(!off.enabled && off.cleanupPending && store.value?.clearDelivered == true)
        #expect(await center.ids == Set(originals.map(\.id)))
        for _ in 0..<3 {
            let repeated = await scheduler.submit(.refresh)
            #expect(!repeated.enabled && repeated.cleanupPending)
        }
        let restarted = engine(store, center, clock)
        #expect(await restarted.submit(.refresh).cleanupPending)
        #expect(store.value?.exposures.count == 14)
        await center.configure(permission: .authorized)
        #expect(await center.ids.count == 14) // Regrant before reopen is the residual window.
        #expect(await restarted.submit(.refresh).cleanupPending) // Ineffective removal.
        await center.configure(holdRemoval: false, holdDeliveredRemoval: false)
        let verified = await restarted.submit(.refresh)
        #expect(!verified.enabled && !verified.cleanupPending)
        #expect(store.value?.clearDelivered == false && store.value?.version == 3)
        #expect(await center.ids.isEmpty)
        #expect(await center.adds.count == 14)
        #expect(store.value?.exposures.count == 14 && store.value?.retired?.count == 14)
        #expect(await engine(store, center, clock).submit(.refresh).cleanupPending == false)
        _ = await restarted.submit(.enable(true))
        #expect(await center.adds.count == 14) // Suppressed dates cannot get new IDs.
    }

    @Test(arguments: [1, 2, 3]) func legacyOffCleanupIsNotInferredFromEmptyFields(version: Int) async throws {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        var old = ReminderJournal(); old.version = version
        old.cleanupPending = version < 3 ? false : nil // Downgraded false is not trusted.
        let target = ReminderCalendar.queue(now: clock.date, zone: clock.zone, time: old.time)[0]
        let entry = ReminderEntry(id: ReminderRequest.prefix + "legacy-retired", target: target, phase: .cancelling)
        old.retired = [entry]; old.remember(entry, through: clock.date)
        store.value = old
        await center.configure(permission: .denied, hideWhileDenied: true)
        let pending = await engine(store, center, clock).submit(.refresh)
        #expect(!pending.enabled && pending.cleanupPending && store.value?.clearDelivered == true)
        #expect(store.value?.retired == [entry] && store.value?.exposures == old.exposures)
        await center.configure(permission: .authorized)
        #expect(await engine(store, center, clock).submit(.refresh).cleanupPending == false)
        #expect(await center.adds.isEmpty)
    }

    @Test func cleanupReadbackUnknownAndAuthorizationRaceRemainPending() async {
        for script in [[ReminderAuthorization.authorized, .authorized, .denied, .authorized], [.authorized, .authorized, .authorized, .denied]] {
            let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
            store.value = ReminderJournal()
            await center.scriptAuthorization(script)
            #expect(await engine(store, center, clock).submit(.refresh).cleanupPending)
            #expect(store.value?.cleanupPending != false && store.value?.clearDelivered == true)
        }
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        store.value = ReminderJournal()
        await center.configure(unknown: true)
        #expect(await engine(store, center, clock).submit(.refresh).cleanupPending)
        #expect(store.value?.clearDelivered == true)
    }

    @Test(arguments: [false, true]) func cleanupClearWriteFailureStaysConservative(committed: Bool) async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        store.value = ReminderJournal()
        // Refresh saves durable cleanup intent, then commits verified cleanup.
        if committed { store.commitThenFailAt = 2 } else { store.failAt = 2 }
        let scheduler = engine(store, center, clock)
        let failure = await scheduler.submit(.refresh)
        #expect(failure.storageBlocked && failure.cleanupPending)
        #expect(await scheduler.submit(.refresh).cleanupPending)
        store.failAt = nil; store.commitThenFailAt = nil
        await center.configure(permission: .denied)
        let restart = await engine(store, center, clock).submit(.refresh)
        // A committed clearing write represents already-completed authorized
        // observations. A pre-commit failure retains the durable pending marker.
        #expect(restart.cleanupPending == !committed)
    }

    @Test func cleanupWordingFollowsCurrentIntent() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        await center.configure(permission: .denied)
        let scheduler = engine(store, center, clock)
        let off = await scheduler.submit(.enable(false))
        #expect(off.cleanupMessage?.contains("turned off") == true)
        let on = await scheduler.submit(.enable(true))
        #expect(on.enabled && on.cleanupPending)
        #expect(on.cleanupMessage?.contains("turned on") == true)
        #expect(on.cleanupMessage?.contains("turned off") == false)
        #expect(await center.permissionRequests == 0)
    }

    @Test func cleanupMissingNullMalformedAndOldReaderVersionContract() throws {
        let encoder = JSONEncoder()
        var object = try JSONSerialization.jsonObject(with: encoder.encode(ReminderJournal())) as! [String: Any]
        for field: Any? in [nil, NSNull()] {
            object["cleanupPending"] = field
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(try JSONDecoder().decode(ReminderJournal.self, from: data).needsCleanupVerification)
        }
        object["cleanupPending"] = "false"
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ReminderJournal.self, from: JSONSerialization.data(withJSONObject: object)) }
        #expect(ReminderJournal().version == 3) // Frozen reader only admits versions 1 and 2.
    }
}

extension ReminderTests {
    @Test(arguments: [false, true]) func legacyDeliveredRetiredCleanupCannotClearPrematurely(enabled: Bool) async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        var state = ReminderJournal(); state.version = 2; state.enabled = enabled
        let target = ReminderCalendar.queue(now: clock.date, zone: clock.zone, time: state.time)[0]
        let old = ReminderEntry(id: ReminderRequest.prefix + "retired-delivered", target: target, phase: .cancelling)
        state.retired = [old]; state.remember(old, through: clock.date)
        state.clearDelivered = false; store.value = state
        await center.seed(["unrelated-pending"], shown: [old.id, "unrelated-delivered"])
        await center.configure(holdDeliveredRemoval: true)
        let scheduler = engine(store, center, clock)
        let first = await scheduler.submit(.refresh)
        #expect(first.cleanupPending && first.enabled == enabled)
        #expect(store.value?.cleanupPending == true)
        #expect(await center.adds.isEmpty)
        #expect(await engine(store, center, clock).submit(.refresh).cleanupPending)
        await center.configure(holdDeliveredRemoval: false)
        // OFF supplies the explicit all-owned delivered cleanup intent. An ON
        // migration does not invent that intent merely to remove the warning.
        let cleaned = await scheduler.submit(.enable(false))
        #expect(!cleaned.cleanupPending && !cleaned.enabled)
        #expect(await center.ids == ["unrelated-pending"])
        #expect(await center.shown == ["unrelated-delivered"])
        #expect(store.value?.exposures == state.exposures && store.value?.retired == state.retired)
    }
}

extension ReminderTests {
    @Test(arguments: [false, true]) func offSaveFailureDoesNotClaimVerifiedOffOrEraseHistory(committed: Bool) async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        let originals = store.value!.entries
        await center.configure(permission: .denied, holdRemoval: true, hideWhileDenied: true)
        if committed { store.commitThenFailAt = store.writes + 1 } else { store.failAt = store.writes + 1 }
        let failed = await scheduler.submit(.enable(false))
        #expect(failed.storageBlocked && failed.cleanupPending)
        #expect(store.value?.enabled == !committed)
        #expect(store.value?.entries == originals)
        store.failAt = nil; store.commitThenFailAt = nil
        let restarted = await engine(store, center, clock).submit(.refresh)
        #expect(restarted.enabled == !committed)
        #expect(restarted.cleanupPending == committed)
        #expect(await center.adds.count == 14)
    }

    @Test func committedClearingFailureDoesNotCancelUnderDurableCleanState() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        let originals = store.value!.entries
        store.value!.cleanupPending = true
        // A restarted writer sees pending; reconcile save, then verification save.
        store.commitThenFailAt = store.writes + 2
        let failed = await engine(store, center, clock).submit(.refresh)
        #expect(failed.storageBlocked && failed.cleanupPending)
        #expect(store.value?.cleanupPending == false)
        #expect(await center.ids == Set(originals.map(\.id)))
        #expect(await center.removals.isEmpty)
        store.commitThenFailAt = nil
        #expect(await engine(store, center, clock).submit(.refresh).queued == 14)
    }
}
