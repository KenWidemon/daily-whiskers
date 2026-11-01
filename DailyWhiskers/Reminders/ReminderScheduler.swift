import Foundation

struct ReminderStatus: Sendable {
    var enabled = false
    var time = ReminderTime()
    var authorization: ReminderAuthorization = .notDetermined
    var queued = 0
    var coverageEnd: Date?
    var message: String?
    var storageBlocked = false
}

enum ReminderCommand: Sendable {
    case refresh
    case enable(Bool)
    case time(ReminderTime)
}

/// All entry points join a task chain. Actor isolation alone is insufficient:
/// add/remove/readback suspend and would otherwise admit interleaved mutations.
actor ReminderScheduler {
    private let client: any ReminderNotificationClient
    private let store: any ReminderJournalStore
    private let now: @Sendable () -> Date
    private let zone: @Sendable () -> TimeZone
    // An app-owned conservative budget, NOT a claim about a modern iOS limit.
    private let pendingBudget: Int
    private var tail: Task<ReminderStatus, Never>?
    private var journal: ReminderJournal?
    private var faulted = false

    init(client: any ReminderNotificationClient, store: any ReminderJournalStore,
         now: @escaping @Sendable () -> Date = { Date() },
         zone: @escaping @Sendable () -> TimeZone = { .current }, pendingBudget: Int = 32) {
        self.client = client; self.store = store; self.now = now; self.zone = zone
        self.pendingBudget = pendingBudget
    }

    func submit(_ command: ReminderCommand) async -> ReminderStatus {
        let previous = tail
        let task = Task {
            _ = await previous?.value
            return await self.perform(command)
        }
        tail = task
        return await task.value
    }

    private func persist(_ value: ReminderJournal) throws {
        try store.save(value)
        journal = value
    }

    private func perform(_ command: ReminderCommand) async -> ReminderStatus {
        var authorization = await client.authorization()
        do {
            guard !faulted else { throw ReminderStorageError.unreadable }
            var state: ReminderJournal
            if let journal { state = journal }
            else if let restored = try store.load() { state = restored; journal = restored }
            else {
                // No ledger + OS-owned requests is not a fresh install. Never
                // synthesize blank history from a missing file or an empty list.
                guard let pending = await client.pending() else { throw ReminderStorageError.unreadable }
                let delivered = await client.delivered()
                if !pending.filter(ReminderRequest.owns).isEmpty ||
                    !delivered.filter(ReminderRequest.owns).isEmpty {
                    var quarantine = ReminderJournal(); quarantine.requiresRecovery = true
                    try persist(quarantine)
                    throw ReminderStorageError.unreadable
                }
                state = ReminderJournal(); try persist(state)
            }
            guard !state.requiresRecovery else { throw ReminderStorageError.unreadable }
            switch command {
            case .refresh: break
            case .enable(let enabled):
                state.enabled = enabled
                if !enabled { state.clearDelivered = true }
                try persist(state)
                if enabled && authorization == .notDetermined {
                    do { try await client.requestAlerts() }
                    catch { return status(state, authorization: await client.authorization(), message: "Couldn't request permission. Try again when you're ready.") }
                    authorization = await client.authorization()
                }
            case .time(let time):
                guard time.isValid else { return status(state, authorization: authorization, message: "Choose a valid reminder time.") }
                state.time = time // Saving the time never sets enabled.
                try persist(state)
            }
            return try await reconcile(state, authorization: authorization)
        } catch {
            // Once a persistence outcome is uncertain, do not issue another add
            // in this process. Preserve the file for recovery; never reset it.
            faulted = true
            let ids = Set((journal?.entries ?? []).map(\.id))
                .union((await client.pending() ?? []).filter(ReminderRequest.owns))
            await client.removePending(ids)
            if case .enable(false) = command {
                await client.removeDelivered(await client.delivered().filter(ReminderRequest.owns))
            }
            var result = status(journal ?? ReminderJournal(), authorization: authorization,
                                message: "Reminders are paused because saved scheduling state couldn't be verified. Reopen the app to retry.")
            result.storageBlocked = true; result.queued = 0; result.coverageEnd = nil
            return result
        }
    }

    private func reconcile(_ initial: ReminderJournal, authorization: ReminderAuthorization) async throws -> ReminderStatus {
        var state = initial
        let observedAt = now()
        let clockReversed = state.lastNow.map { observedAt < $0 } ?? false
        state.lastNow = max(state.lastNow ?? observedAt, observedAt)
        let desired = ReminderCalendar.queue(now: observedAt, zone: zone(), time: state.time)
        let canAdd = state.enabled && authorization.canSchedule && !clockReversed
        var pending = await client.pending()
        let originalPending = pending
        let knownIDs = Set(state.entries.map(\.id))
        let unknown = (pending ?? []).filter { ReminderRequest.owns($0) && !knownIDs.contains($0) }
        if !unknown.isEmpty {
            state.requiresRecovery = true; try persist(state)
            await client.removePending(unknown)
            // Cannot reconstruct eligibility from an unknown request identifier.
            throw ReminderStorageError.unreadable
        }
        // Decide cancellation before the capacity gate. A nil inventory must not
        // leave known old-zone requests active after travel/reopening.
        var cancelling: [ReminderEntry] = []
        for index in state.entries.indices {
            let entry = state.entries[index]
            if entry.target.date <= observedAt { state.remember(entry, through: observedAt) }
            let keep = canAdd && entry.phase == .pending && entry.target.date > observedAt &&
                desired.contains(entry.target) && !state.blocks(entry.target, now: observedAt) &&
                (pending?.contains(entry.id) ?? true)
            if !keep {
                cancelling.append(entry)
                state.entries[index].phase = .cancelling
            }
        }
        try persist(state)
        if state.clearDelivered {
            // Clearing already-delivered reminders does not depend on pending
            // capacity or cancellation readback succeeding.
            await client.removeDelivered(await client.delivered().filter(ReminderRequest.owns))
            if await client.delivered().filter(ReminderRequest.owns).isEmpty {
                state.clearDelivered = false; try persist(state)
            }
        }
        let cancelIDs = Set(cancelling.map(\.id))
        if !cancelIDs.isEmpty {
            await client.removePending(cancelIDs)
            // These are observations of removal, not an atomic delivery barrier.
            let first = await client.pending()
            let second = await client.pending()
            let checkedAt = now()
            for entry in cancelling {
                let absent = first.map { !$0.contains(entry.id) } == true && second.map { !$0.contains(entry.id) } == true
                // Only a previously acknowledged, still-pending request removed
                // comfortably before its target can release a future reservation.
                // Interrupted intents/cancellations and missing requests retain
                // uncertainty regardless of empty pending/delivered lists.
                let earlyObservedRemoval = entry.phase == .pending && originalPending?.contains(entry.id) == true &&
                    entry.target.date.timeIntervalSince(checkedAt) > 60 && absent && !clockReversed && checkedAt >= observedAt
                if !earlyObservedRemoval { state.remember(entry, through: checkedAt) }
                if absent { state.entries.removeAll { $0.id == entry.id } }
            }
            try persist(state)
            pending = second
            if !state.entries.filter({ $0.phase == .cancelling }).isEmpty {
                return status(state, authorization: authorization, message: "Waiting for iOS to confirm removal. Reminders will be checked when you reopen the app.")
            }
        }
        if state.clearDelivered {
            return status(state, authorization: authorization, message: "Delivered reminders are still being cleared. Reopen the app to check again.")
        }
        if clockReversed { return status(state, authorization: authorization, message: "Reminders are paused after a clock change to avoid duplicates. Reopen after the clock catches up.") }
        guard canAdd else { return status(state, authorization: authorization) }
        guard var inventory = pending else {
            return status(state, authorization: authorization, message: "Couldn't verify the notification queue. Reopen the app to retry.")
        }
        for target in desired {
            let at = now()
            guard at >= observedAt else { return status(state, authorization: authorization, message: "The clock changed during scheduling. Reopen the app to reconcile reminders.") }
            guard target.date > at, !state.blocks(target, now: at),
                  !state.entries.contains(where: { $0.target.day == target.day }),
                  inventory.count < pendingBudget else { continue }
            let entry = ReminderEntry(id: ReminderRequest.prefix + UUID().uuidString, target: target, phase: .intent)
            state.entries.append(entry)
            try persist(state) // Durable intent MUST precede add.
            let beforeAdd = now()
            guard beforeAdd >= at, target.date > beforeAdd else {
                state.remember(entry, through: beforeAdd)
                state.entries.removeAll { $0.id == entry.id }
                try persist(state)
                return status(state, authorization: authorization, message: "The time changed while preparing reminders. Reopen the app to check again.")
            }
            do { try await client.add(id: entry.id, target: target) }
            catch {
                state.remember(entry, through: now())
                state.entries[state.entries.count - 1].phase = .cancelling
                try persist(state)
                await client.removePending([entry.id])
                return status(state, authorization: authorization, message: "Couldn't finish scheduling. Reopen the app to safely retry.")
            }
            state.entries[state.entries.count - 1].phase = .pending
            try persist(state)
            // A successful completion alone does not establish retained capacity.
            let fresh = await client.pending()
            let expected = Set(state.entries.filter { $0.phase == .pending && $0.target.date > now() }.map(\.id))
            guard let fresh, fresh.contains(entry.id), expected.isSubset(of: fresh) else {
                // Detect retention loss elsewhere in the batch as well as loss
                // of the just-added request. A unique ID is not deduplication.
                let missing = state.entries.filter { fresh?.contains($0.id) != true || $0.id == entry.id }
                for lost in missing {
                    state.remember(lost, through: now())
                    if let index = state.entries.firstIndex(where: { $0.id == lost.id }) { state.entries[index].phase = .cancelling }
                }
                try persist(state)
                await client.removePending(Set(missing.map(\.id)))
                return status(state, authorization: authorization, message: "iOS didn't confirm the reminder queue. Reopen the app to check again.")
            }
            inventory = fresh
        }
        return status(state, authorization: authorization)
    }

    private func status(_ state: ReminderJournal, authorization: ReminderAuthorization, message: String? = nil) -> ReminderStatus {
        let future = state.entries.filter { $0.phase == .pending && $0.target.date > now() }
        return ReminderStatus(enabled: state.enabled, time: state.time, authorization: authorization,
            queued: future.count, coverageEnd: future.map(\.target.date).max(), message: message)
    }
}
