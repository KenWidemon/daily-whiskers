import Foundation

struct ReminderStatus: Sendable {
    var enabled = false
    var time = ReminderTime()
    var authorization: ReminderAuthorization = .notDetermined
    var queued = 0
    var coverageEnd: Date?
    var message: String?
    var storageBlocked = false
    var cleanupPending = false
    var cleanupMessage: String? {
        guard cleanupPending else { return nil }
        let intent = enabled
            ? "Reminders are turned on in Daily Whiskers, but cleanup of earlier reminders is not yet verified."
            : "Reminders are turned off in Daily Whiskers, but cleanup of previously scheduled reminders is not yet verified."
        return intent + " Earlier reminders may still appear until cleanup is checked. Previously scheduled reminders may still appear if you allow notifications again before reopening the app. Reopen after changing permission so Daily Whiskers can finish checking cleanup."
    }
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
    private var storageFailureMessage: String?
    private var confirmedPending: Set<String> = []

    init(client: any ReminderNotificationClient, store: any ReminderJournalStore,
         now: @escaping @Sendable () -> Date = { Date() },
         zone: @escaping @Sendable () -> TimeZone = { .current }, pendingBudget: Int = 32) {
        self.client = client; self.store = store; self.now = now; self.zone = zone
        self.pendingBudget = pendingBudget
    }

    func submit(_ command: ReminderCommand) async -> ReminderStatus {
        await enqueue(command).value
    }

    /// Registration is synchronous on the actor; waiting never changes queue order.
    func enqueue(_ command: ReminderCommand) -> Task<ReminderStatus, Never> {
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
        ReminderCommandTrace.record("scheduler.command.enqueued", command: command)
#endif
        let previous = tail
        let task = Task {
            _ = await previous?.value
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
            ReminderCommandTrace.record("scheduler.command.enter", command: command)
            let result = await self.perform(command)
            ReminderCommandTrace.record("scheduler.command.result", command: command, status: result)
            return result
#else
            return await self.perform(command)
#endif
        }
        tail = task
        return task
    }

    private func persist(_ value: ReminderJournal) throws {
        var upgraded = value
        upgraded.version = 3
        if upgraded.cleanupPending == nil { upgraded.cleanupPending = true }
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
        ReminderCommandTrace.record("storage.persist.begin", enabled: upgraded.enabled)
        do { try store.save(upgraded) }
        catch {
            ReminderCommandTrace.record("storage.persist.error", enabled: upgraded.enabled, error: error)
            throw error
        }
#else
        try store.save(upgraded)
#endif
        journal = upgraded
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
        ReminderCommandTrace.record("storage.persist.verified", enabled: upgraded.enabled)
#endif
    }

    private func perform(_ command: ReminderCommand) async -> ReminderStatus {
        confirmedPending = []
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
        ReminderCommandTrace.record("authorization.read.begin", command: command)
#endif
        var authorization = await client.authorization()
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
        ReminderCommandTrace.record("authorization.read.complete", command: command, authorization: authorization)
#endif
        do {
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
            ReminderCommandTrace.record("scheduler.state.begin", command: command)
#endif
            guard !faulted else { throw ReminderStorageError.unreadable }
            var state: ReminderJournal
            if let journal { state = journal }
            else if var restored = try store.load() {
                // A legacy writer could ignore new fields; never trust a false
                // marker carried in a v1/v2 journal after a downgrade.
                if restored.version < 3 { restored.cleanupPending = true; restored.version = 3 }
                state = restored; journal = restored
            }
            else {
                // No ledger + OS-owned requests is not a fresh install. Never
                // synthesize blank history from a missing file or an empty list.
                guard let pending = await client.pending() else { throw ReminderStorageError.verification }
                let delivered = await client.delivered()
                if !pending.filter(ReminderRequest.owns).isEmpty ||
                    !delivered.filter(ReminderRequest.owns).isEmpty {
                    var quarantine = ReminderJournal(); quarantine.requiresRecovery = true
                    try persist(quarantine)
                    throw ReminderStorageError.quarantined
                }
                state = ReminderJournal(); try persist(state)
            }
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
            ReminderCommandTrace.record("scheduler.state.ready", command: command, enabled: state.enabled)
#endif
            if state.requiresRecovery {
                // A verified quarantine may record OFF, but never erase history,
                // enable scheduling, or repair missing provenance implicitly.
                if case .enable(false) = command {
                    state.enabled = false; state.clearDelivered = true; state.cleanupPending = true
                    try persist(state)
                }
                throw ReminderStorageError.quarantined
            }
            switch command {
            case .refresh: break
            case .enable(let enabled):
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
                ReminderCommandTrace.record("scheduler.enable.intent", command: command, enabled: enabled)
#endif
                state.enabled = enabled
                if !enabled { state.clearDelivered = true; state.cleanupPending = true }
                try persist(state)
                if enabled && authorization == .notDetermined {
                    do {
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
                        ReminderCommandTrace.record("authorization.request.begin", command: command)
#endif
                        try await client.requestAlerts()
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
                        ReminderCommandTrace.record("authorization.request.complete", command: command)
#endif
                    }
                    catch {
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
                        ReminderCommandTrace.record("authorization.request.error", command: command, error: error)
#endif
                        return status(state, authorization: await client.authorization(), message: "Couldn't request permission. Try again when you're ready.")
                    }
                    authorization = await client.authorization()
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
                    ReminderCommandTrace.record("authorization.read.complete", command: command, authorization: authorization)
#endif
                }
            case .time(let time):
                guard time.isValid else { return status(state, authorization: authorization, message: "Choose a valid reminder time.") }
                state.time = time // Saving the time never sets enabled.
                try persist(state)
            }
            return try await reconcile(state, authorization: authorization)
        } catch {
#if DEBUG && CI_SMOKE_TESTING && CI_DIAGNOSTIC_TESTING
            ReminderCommandTrace.record("scheduler.command.error", command: command, authorization: authorization, error: error)
#endif
            // Once a persistence outcome is uncertain, do not issue another add
            // in this process. Preserve the file for recovery; never reset it.
            if case ReminderStorageError.quarantined = error {
                // The quarantine is verified state, unlike an uncertain write.
                // Keep accepting OFF intent while continuing to reject additions.
            } else { faulted = true }
            if storageFailureMessage == nil {
                switch error as? ReminderStorageError {
                case .quarantined, .unreadable:
                    storageFailureMessage = "Reminders are paused because saved scheduling history needs recovery. Reopening won't repair it. Contact Support from Settings. Your saved history hasn't been reset."
                default:
                    storageFailureMessage = "Reminders are paused because saved scheduling state couldn't be verified. Close the app completely, then reopen to recheck. If this continues, contact Support from Settings. Your saved history hasn't been reset."
                }
            }
            let ids = Set(((journal?.entries ?? []) + (journal?.retired ?? [])).map(\.id))
                .union((await client.pending() ?? []).filter(ReminderRequest.owns))
            // Do not start another cancellation after a failed write unless a
            // durable cleanup marker already exists. A failed OFF save cannot
            // be described as saved OFF; the storage warning remains explicit.
            // Re-read: a clearing save may have committed before throwing.
            // The cached pending marker alone cannot authorize more removals.
            let durableCleanup = (try? store.load())?.needsCleanupVerification == true
            if durableCleanup { await client.removePending(ids) }
            let explicitOff: Bool
            if case .enable(false) = command { explicitOff = true } else { explicitOff = false }
            if durableCleanup && (explicitOff || journal?.clearDelivered == true) {
                await client.removeDelivered(await client.delivered().filter(ReminderRequest.owns))
                // Keep the durable cleanup intent in quarantine; retry on reopen.
            }
            var result = status(journal ?? ReminderJournal(), authorization: authorization,
                                message: storageFailureMessage)
            result.storageBlocked = true; result.cleanupPending = true; result.queued = 0; result.coverageEnd = nil
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
        let requests = await client.pendingRequests()
        var pending = requests.map { Set($0.map(\.id)) }
        let originalPending = pending
        // Restore returning retired IDs as cancellation intents before any add.
        // Their prior absence was not proof that iOS could never return them.
        _ = restoreRetired(requests, state: &state, observedAt: observedAt)
        let invalid = conflictingRequests(requests, state: state)
        if !invalid.isEmpty {
            state.requiresRecovery = true; state.cleanupPending = true; try persist(state)
            await client.removePending(invalid)
            // Unknown IDs and conflicting trigger/content cannot establish lineage.
            throw ReminderStorageError.quarantined
        }
        confirmedPending = matchingPending(requests, state: state)
        // Positive delivery evidence wins over a simultaneous future pending
        // copy (for example after a clock change). Empty lists prove nothing.
        let delivered = await client.delivered()
        for entry in state.entries where delivered.contains(entry.id) {
            state.remember(entry, through: observedAt)
        }
        // Decide cancellation before the capacity gate. A nil inventory must not
        // leave known old-zone requests active after travel/reopening.
        var cancelling: [ReminderEntry] = []
        for index in state.entries.indices {
            let entry = state.entries[index]
            if entry.target.date <= observedAt { state.remember(entry, through: observedAt) }
            // Permission denial alone never cancels an unchanged, enabled
            // acknowledged request. iOS may hide it; absence while denied is not
            // permission to add it again. Legacy suspension may have cancelled.
            let eligibleOriginal = state.enabled && !clockReversed && state.permissionSuspended != true &&
                entry.phase == .pending && entry.target.date > observedAt &&
                desired.contains(entry.target) && !state.blocks(entry.target, now: observedAt)
            let keep = eligibleOriginal && (!authorization.canSchedule || requests == nil || confirmedPending.contains(entry.id))
            if !keep {
                cancelling.append(entry)
                state.entries[index].phase = .cancelling
            }
        }
        if !state.enabled && state.needsCleanupVerification { state.clearDelivered = true }
        if !cancelling.isEmpty || state.clearDelivered { state.cleanupPending = true }
        try persist(state) // Cleanup uncertainty is durable before removal.
        if state.clearDelivered {
            // Clearing already-delivered reminders does not depend on pending
            // capacity or cancellation readback succeeding.
            await client.removeDelivered(await client.delivered().filter(ReminderRequest.owns))
        }
        let cancelIDs = Set(cancelling.map(\.id))
        if !cancelIDs.isEmpty {
            await client.removePending(cancelIDs)
            confirmedPending.subtract(cancelIDs)
            // These are observations of removal, not an atomic delivery barrier.
            let firstRequests = await client.pendingRequests()
            let secondRequests = await client.pendingRequests()
            let first = firstRequests.map { Set($0.map(\.id)) }
            let second = secondRequests.map { Set($0.map(\.id)) }
            let removalAuthorization = await client.authorization()
            let checkedAt = now()
            for entry in cancelling {
                let absent = first.map { !$0.contains(entry.id) } == true && second.map { !$0.contains(entry.id) } == true
                // Only a previously acknowledged, still-pending request removed
                // comfortably before its target can release a future reservation.
                // Interrupted intents/cancellations and missing requests retain
                // uncertainty regardless of empty pending/delivered lists.
                let earlyObservedRemoval = authorization.canSchedule && removalAuthorization.canSchedule && entry.phase == .pending && originalPending?.contains(entry.id) == true &&
                    entry.target.date.timeIntervalSince(checkedAt) > 60 && absent && !clockReversed && checkedAt >= observedAt
                if !earlyObservedRemoval { state.remember(entry, through: checkedAt) }
                if absent {
                    if state.retired == nil { state.retired = [] }
                    state.retired?.append(ReminderEntry(id: entry.id, target: entry.target, phase: .cancelling))
                    state.entries.removeAll { $0.id == entry.id }
                }
            }
            let conflicts = conflictingRequests(firstRequests, state: state)
                .union(conflictingRequests(secondRequests, state: state))
            if !conflicts.isEmpty {
                state.requiresRecovery = true; state.cleanupPending = true; try persist(state)
                await client.removePending(conflicts)
                throw ReminderStorageError.quarantined
            }
            let returned = restoreRetired((firstRequests ?? []) + (secondRequests ?? []), state: &state, observedAt: checkedAt)
            let lateCancellation = markBlockedByReturn(returned, state: &state, observedAt: checkedAt)
            confirmedPending = matchingPending(secondRequests, state: state)
            try persist(state)
            if !lateCancellation.isEmpty { await client.removePending(lateCancellation) }
            pending = second
            if !removalAuthorization.canSchedule {
                return status(state, authorization: removalAuthorization,
                    message: "Notification permission changed. Reopen the app to check reminders.")
            }
            if !state.entries.filter({ $0.phase == .cancelling }).isEmpty {
                return status(state, authorization: authorization, message: "Waiting for iOS to confirm removal. Reminders will be checked when you reopen the app.")
            }
        }
        if state.permissionSuspended != nil {
            state.permissionSuspended = nil
            try persist(state)
        }
        let cleanupAuthorization = try await verifyCleanup(&state)
        if state.needsCleanupVerification {
            return status(state, authorization: cleanupAuthorization ?? authorization)
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
            let latestAuthorization = await client.authorization()
            guard latestAuthorization.canSchedule else {
                return status(state, authorization: latestAuthorization)
            }
            let entry = ReminderEntry(id: ReminderRequest.prefix + UUID().uuidString, target: target, phase: .intent)
            state.entries.append(entry)
            // A failed/uncertain add may need cancellation. Persist that
            // possibility before the notification side effect as well.
            state.cleanupPending = true
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
                state.cleanupPending = true
                try persist(state)
                await client.removePending([entry.id])
                return status(state, authorization: authorization, message: "Couldn't finish scheduling. Reopen the app to safely retry.")
            }
            state.entries[state.entries.count - 1].phase = .pending
            try persist(state)
            // A successful completion alone does not establish retained capacity.
            let freshRequests = await client.pendingRequests()
            let freshAuthorization = await client.authorization()
            let fresh = freshRequests.map { Set($0.map(\.id)) }
            let conflicts = conflictingRequests(freshRequests, state: state)
            if !conflicts.isEmpty {
                state.requiresRecovery = true; state.cleanupPending = true; try persist(state)
                await client.removePending(conflicts)
                throw ReminderStorageError.quarantined
            }
            let returned = restoreRetired(freshRequests, state: &state, observedAt: now())
            confirmedPending = matchingPending(freshRequests, state: state)
            if !returned.isEmpty {
                let cancel = markBlockedByReturn(returned, state: &state, observedAt: now())
                confirmedPending.subtract(cancel)
                try persist(state)
                await client.removePending(cancel)
                return status(state, authorization: freshAuthorization, message: "The notification queue changed. Reopen the app to check reminders.")
            }
            guard freshAuthorization.canSchedule else {
                return status(state, authorization: freshAuthorization)
            }
            let expected = Set(state.entries.filter { $0.phase == .pending && $0.target.date > now() }.map(\.id))
            guard let fresh, confirmedPending.contains(entry.id), expected.isSubset(of: confirmedPending) else {
                // Detect retention loss elsewhere in the batch as well as loss
                // of the just-added request. A unique ID is not deduplication.
                let missing = state.entries.filter { fresh?.contains($0.id) != true || $0.id == entry.id }
                for lost in missing {
                    state.remember(lost, through: now())
                    if let index = state.entries.firstIndex(where: { $0.id == lost.id }) { state.entries[index].phase = .cancelling }
                }
                state.cleanupPending = true
                try persist(state)
                await client.removePending(Set(missing.map(\.id)))
                return status(state, authorization: authorization, message: "iOS didn't confirm the reminder queue. Reopen the app to check again.")
            }
            inventory = fresh
        }
        let finalAuthorization = try await verifyCleanup(&state)
        return status(state, authorization: finalAuthorization ?? authorization)
    }

    /// Bounded observations only. Authorization can change between samples;
    /// neither this check nor OFF can guarantee silence before the next reopen.
    private func verifyCleanup(_ state: inout ReminderJournal) async throws -> ReminderAuthorization? {
        guard state.needsCleanupVerification else { return nil }
        let before = await client.authorization()
        guard before.canSchedule else { return before }
        let first = await client.pendingRequests()
        let firstDelivered = await client.delivered()
        let between = await client.authorization()
        let second = await client.pendingRequests()
        let secondDelivered = await client.delivered()
        let after = await client.authorization()
        let conflicts = conflictingRequests(first, state: state).union(conflictingRequests(second, state: state))
        if !conflicts.isEmpty {
            state.requiresRecovery = true; state.cleanupPending = true; try persist(state)
            await client.removePending(conflicts)
            throw ReminderStorageError.quarantined
        }
        guard between.canSchedule, after.canSchedule, let first, let second else { return after }
        // Exact-match active ON originals may remain. Missing originals are not
        // restored or re-added here. OFF requires both owned inventories empty.
        let allowed = state.enabled ? Set(state.entries.filter { $0.phase == .pending }.map(\.id)) : []
        guard [first, second].allSatisfy({ requests in
            Set(requests.map(\.id).filter(ReminderRequest.owns)).isSubset(of: allowed)
        }), [firstDelivered, secondDelivered].allSatisfy({ delivered in
            let allowedDelivered = state.clearDelivered ? Set<String>() : allowed
            return Set(delivered.filter(ReminderRequest.owns)).isSubset(of: allowedDelivered)
        })
        else { return after }
        // Keep the last verified in-memory journal pending if this write throws.
        var verified = state
        verified.cleanupPending = false
        verified.clearDelivered = false
        try persist(verified)
        state = verified
        return after
    }

    private func markBlockedByReturn(_ returned: Set<String>, state: inout ReminderJournal,
                                     observedAt: Date) -> Set<String> {
        guard !returned.isEmpty else { return [] }
        state.cleanupPending = true
        var cancel = returned
        for index in state.entries.indices where state.blocks(state.entries[index].target, now: observedAt) {
            state.entries[index].phase = .cancelling
            cancel.insert(state.entries[index].id)
        }
        return cancel
    }

    private func restoreRetired(_ requests: [ReminderPendingRequest]?, state: inout ReminderJournal,
                                observedAt: Date) -> Set<String> {
        let ids = Set((requests ?? []).map(\.id))
        let returning = (state.retired ?? []).filter { ids.contains($0.id) }
        for var entry in returning {
            entry.phase = .cancelling
            state.remember(entry, through: observedAt)
            state.entries.append(entry)
        }
        let restored = Set(returning.map(\.id))
        if !restored.isEmpty {
            state.cleanupPending = true
            state.retired?.removeAll { restored.contains($0.id) }
        }
        return restored
    }

    private func conflictingRequests(_ requests: [ReminderPendingRequest]?, state: ReminderJournal) -> Set<String> {
        var seen: Set<String> = []
        var invalid: Set<String> = []
        for request in requests ?? [] where ReminderRequest.owns(request.id) {
            guard seen.insert(request.id).inserted,
                  let entry = (state.entries + (state.retired ?? [])).first(where: { $0.id == request.id }),
                  ReminderRequest.matches(request, id: entry.id, target: entry.target)
            else { invalid.insert(request.id); continue }
        }
        return invalid
    }

    private func matchingPending(_ requests: [ReminderPendingRequest]?, state: ReminderJournal) -> Set<String> {
        Set((requests ?? []).compactMap { request in
            guard let entry = state.entries.first(where: { $0.id == request.id && $0.phase == .pending }),
                  ReminderRequest.matches(request, id: entry.id, target: entry.target) else { return nil }
            return request.id
        })
    }

    private func status(_ state: ReminderJournal, authorization: ReminderAuthorization, message: String? = nil) -> ReminderStatus {
        let future = state.entries.filter { authorization.canSchedule && state.permissionSuspended != true && confirmedPending.contains($0.id) && $0.phase == .pending && $0.target.date > now() }
        return ReminderStatus(enabled: state.enabled, time: state.time, authorization: authorization,
            queued: future.count, coverageEnd: future.map(\.target.date).max(), message: message,
            cleanupPending: state.needsCleanupVerification)
    }
}
