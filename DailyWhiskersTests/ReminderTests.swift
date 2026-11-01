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
    var failLoad = false
    var afterSave: ((Int) -> Void)?
    func load() throws -> ReminderJournal? {
        if failLoad { throw ReminderStorageError.unreadable }; return value
    }
    func save(_ journal: ReminderJournal) throws {
        writes += 1
        if failAt == writes { throw ReminderStorageError.verification }
        value = journal
        afterSave?(writes)
    }
}

private actor ReminderFakeCenter: ReminderNotificationClient {
    var permission: ReminderAuthorization = .authorized
    var ids: Set<String> = []
    var shown: Set<String> = []
    var adds: [ReminderTarget] = []
    var removals: [Set<String>] = []
    var permissionRequests = 0
    var requestOutcome: ReminderAuthorization = .authorized
    var inventoryUnknown = false
    var loseAfterAdd = false
    var failAdd = false
    var holdRemoval = false
    var evictExisting = false
    var addInFlight = 0
    var maximumAddsInFlight = 0
    func authorization() -> ReminderAuthorization { permission }
    func requestAlerts() { permissionRequests += 1; permission = requestOutcome }
    func pending() -> Set<String>? { inventoryUnknown ? nil : ids }
    func delivered() -> Set<String> { shown }
    func add(id: String, target: ReminderTarget) async throws {
        addInFlight += 1; maximumAddsInFlight = max(maximumAddsInFlight, addInFlight)
        await Task.yield()
        defer { addInFlight -= 1 }
        adds.append(target)
        if evictExisting, let first = ids.first { ids.remove(first) }
        if !loseAfterAdd { ids.insert(id) }
        if failAdd { throw ReminderStorageError.verification }
    }
    func removePending(_ values: Set<String>) { removals.append(values); if !holdRemoval { ids.subtract(values) } }
    func removeDelivered(_ values: Set<String>) { shown.subtract(values) }
    func configure(permission: ReminderAuthorization? = nil, unknown: Bool? = nil,
                   loseAfterAdd: Bool? = nil, failAdd: Bool? = nil, holdRemoval: Bool? = nil, evictExisting: Bool? = nil,
                   requestOutcome: ReminderAuthorization? = nil) {
        if let permission { self.permission = permission }
        if let unknown { inventoryUnknown = unknown }
        if let loseAfterAdd { self.loseAfterAdd = loseAfterAdd }
        if let failAdd { self.failAdd = failAdd }
        if let holdRemoval { self.holdRemoval = holdRemoval }
        if let evictExisting { self.evictExisting = evictExisting }
        if let requestOutcome { self.requestOutcome = requestOutcome }
    }
    func seed(_ ids: Set<String>, shown: Set<String> = []) { self.ids = ids; self.shown = shown }
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

    @Test func revocationRetainsIntentRegrantOnlyResumesIfEnabledAndDisableClearsOnlyOwned() async {
        let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
        let scheduler = engine(store, center, clock)
        _ = await scheduler.submit(.enable(true))
        await center.configure(permission: .denied)
        let denied = await scheduler.submit(.refresh)
        #expect(denied.enabled && denied.authorization == .denied && denied.queued == 0)
        #expect(await center.permissionRequests == 0)
        await center.configure(permission: .authorized)
        #expect(await scheduler.submit(.refresh).queued == 14)
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
        await center.seed([entry.id])
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
        for failAt in [4, 5] {
            let store = ReminderMemoryStore(), center = ReminderFakeCenter(), clock = ReminderTestClock()
            store.failAt = failAt
            let scheduler = engine(store, center, clock)
            let result = await scheduler.submit(.enable(true))
            #expect(result.storageBlocked)
            #expect(await center.adds.count == (failAt == 4 ? 0 : 1))
            _ = await scheduler.submit(.refresh)
            #expect(await center.adds.count == (failAt == 4 ? 0 : 1))
            store.failAt = nil
            _ = await engine(store, center, clock).submit(.refresh)
            if failAt == 5 { #expect(store.value?.exposures.count == 1) }
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
        var value = ReminderJournal(); value.version = 2
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
        store.afterSave = { write in if write == 4 { clock.date = instant("2027-01-10T14:00:01Z") } }
        let result = await engine(store, center, clock).submit(.enable(true))
        #expect(result.message != nil && result.queued == 0)
        #expect(await center.adds.isEmpty)
        #expect(store.value?.exposures.first?.day == "2027-01-10")
    }
}
