import Testing
import UIKit
import SQLite3
@testable import DailyWhiskers

@Suite("Mischievous Bonus transaction", .serialized)
@MainActor
struct MischievousCardsTests {
    private let start = ISO8601DateFormatter().date(from: "2026-01-01T12:00:00Z")!
    private func clock(_ offset: TimeInterval = 0) -> MischiefClock {
        MischiefClock(date: start.addingTimeInterval(offset), elapsed: offset + 100)
    }
    private func day(_ clock: MischiefClock, zone: String = "UTC") -> BonusDay {
        BonusDay(date: clock.date, timeZone: TimeZone(identifier: zone)!)
    }
    private func location() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("cards.sqlite")
    }
    private func sql(_ url: URL, _ text: String) throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, text, nil, nil, nil) == SQLITE_OK)
    }
    private func fixture(_ url: URL, state: MischiefState) throws {
        let hex = try JSONEncoder().encode(state).map { String(format: "%02x", $0) }.joined()
        try sql(url, "UPDATE mischief_state SET state=x'\(hex)' WHERE id=1")
    }
    private func seed(winning dates: [BonusDay], losing: [BonusDay] = []) -> String {
        for n in 0..<100_000 {
            let seed = "test-\(n)"
            if dates.allSatisfy({ MischiefState.selected(seed: seed, day: $0.key) }) &&
                losing.allSatisfy({ !MischiefState.selected(seed: seed, day: $0.key) }) { return seed }
        }
        fatalError("No deterministic seed found")
    }
    private func prepare(_ url: URL, winning dates: [BonusDay], losing: [BonusDay] = []) async throws -> CardRepository {
        let repo = CardRepository(url: url, clock: clock())
        var state = try await repo.mischiefState()
        state.seed = seed(winning: dates, losing: losing)
        state.enabled = true
        try fixture(url, state: state)
        return repo
    }
    private func today() throws -> RetainedCard {
        try CardSnapshot.capture(card: DailyContentProvider.fallbackCard,
                                 artwork: BundledCardArtwork.bytes(for: DailyContentProvider.fallbackCard))
    }
    private func bonus(_ repo: CardRepository, at time: MischiefClock) async throws -> RetainedCard {
        try await repo.bonus(on: day(time), today: today(), candidates: DailyContentProvider().bonusCandidates, clock: time)
    }

    @Test func defaultOffAndShadowExcludedFromTodayPool() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repo = CardRepository(url: url, clock: clock())
        #expect(try await repo.mischiefState().enabled == false)
        #expect(!DailyContentProvider().bonusCandidates.contains { $0.id == ShadowLordCard.card.id })
        #expect(try await bonus(repo, at: clock()).snapshot.cardID != ShadowLordCard.card.id)
        let original = try ShadowLordCard.capture()
        #expect(ArtworkIdentity.checksum(original.artwork) == ShadowLordCard.artworkChecksum)
        #expect(original.snapshot.quote == "Today we conquer our enemies. After a nap.")
    }

    @Test func stableTenPercentSelectionAndEligibilityIsNotGuarantee() {
        let results = (0..<10_000).map { MischiefState.selected(seed: "installation-\($0)", day: "2026-01-01") }
        let count = results.filter { $0 }.count
        #expect((850...1150).contains(count)) // Fixed deterministic distribution, not a flaky random test.
        #expect(results == (0..<10_000).map { MischiefState.selected(seed: "installation-\($0)", day: "2026-01-01") })
        #expect(MischiefState.selected(seed: "test-0", day: "2026-01-01") == MischiefState.selected(seed: "test-0", day: day(clock()).key))
    }

    @Test func fourteenFullDaysBoundaryDSTAndTimeZones() throws {
        var state = MischiefState(); state.enabled = true; state.lastReveal = start; state.highWater = start
        let boundary = MischiefState.cooldown
        for offset in [boundary - 1, boundary, boundary + 1] {
            let time = clock(offset)
            try state.observe(time, previous: clock())
            for zone in ["UTC", "America/New_York", "Pacific/Kiritimati", "Pacific/Honolulu"] {
                #expect(state.eligible(on: day(time, zone: zone), at: time) == (offset >= boundary))
            }
        }
        let spring = ISO8601DateFormatter().date(from: "2026-03-01T17:00:00Z")!
        state.lastReveal = spring; state.highWater = spring
        let sameLocalHour = MischiefClock(date: spring.addingTimeInterval(boundary - 3600), elapsed: boundary)
        #expect(!state.eligible(on: day(sameLocalHour, zone: "America/New_York"), at: sameLocalHour))
    }

    @Test func ordinaryDayNeverUpgradesAfterToggleAndLosingDayDoesNotReveal() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = clock(), next = clock(86400)
        let repo = try await prepare(url, winning: [day(first)], losing: [day(next)])
        try await repo.setMischiefEnabled(false, clock: first)
        let ordinary = try await bonus(repo, at: first)
        try await repo.setMischiefEnabled(true, clock: first)
        #expect(try await bonus(repo, at: first).snapshot == ordinary.snapshot)
        #expect(try await bonus(repo, at: next).snapshot.cardID != ShadowLordCard.card.id)
        #expect(try await repo.mischiefState().lastReveal == nil)
    }

    @Test func revealRevisitRelaunchToggleClearSaveShareBackupAndFreshInstall() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = clock(), next = clock(86400), later = clock(MischiefState.cooldown)
        let repo = try await prepare(url, winning: [day(first), day(later)])
        let shadow = try await bonus(repo, at: first)
        #expect(shadow.snapshot.cardID == ShadowLordCard.card.id)
        try await repo.save(shadow)
        try await repo.setMischiefEnabled(false, clock: next)
        let reopened = CardRepository(url: url, clock: clock(86400))
        let retained = try #require(await reopened.retainedBonus(on: day(first)))
        #expect(retained.snapshot == shadow.snapshot)
        #expect(try await reopened.favorites().map(\.id) == [shadow.snapshot.id])
        #expect(try await bonus(reopened, at: next).snapshot.cardID != ShadowLordCard.card.id)
        try await reopened.clearFavorites()
        #expect(try await reopened.load(shadow.snapshot.id).artwork == shadow.artwork)
        let (lease, shared) = try await reopened.beginShare(shadow.snapshot.id)
        #expect(try DailyCardShareRenderer.render(DailyCardShareSnapshot(retained: shared)).text.contains(shadow.snapshot.quote))
        try await reopened.endShare(lease)
        try await reopened.setMischiefEnabled(true, clock: next)
        #expect(try await reopened.mischiefState().lastReveal == first.date)
        #expect(try await bonus(reopened, at: later).snapshot == shadow.snapshot)
        #expect(try await reopened.mischiefState().lastReveal == later.date)
        let backup = url.deletingLastPathComponent().appendingPathComponent("backup.sqlite")
        try await reopened.backup(to: backup)
        let restoredState = try await CardRepository(url: backup).mischiefState()
        #expect(restoredState == (try await reopened.mischiefState()))
        let fresh = url.deletingLastPathComponent().appendingPathComponent("fresh.sqlite")
        #expect(try await CardRepository(url: fresh).mischiefState().enabled == false)
    }

    @Test func clockRollbackForwardJumpSleepAndRelaunchHold() async throws {
        var state = MischiefState(); state.enabled = true
        try state.observe(clock(86400), previous: clock()) // Includes time spent asleep.
        #expect(state.blockedUntil == nil)
        try state.observe(clock(), previous: clock(86400))
        #expect(!state.eligible(on: day(clock()), at: clock()))
        let jumped = MischiefClock(date: start.addingTimeInterval(30 * 86400), elapsed: clock(86400).elapsed + 1)
        try state.observe(jumped, previous: clock(86400))
        #expect(state.blockedUntil == jumped.date.addingTimeInterval(MischiefState.cooldown))
        #expect(!state.eligible(on: day(jumped), at: jumped))
        let restored = try JSONDecoder().decode(MischiefState.self, from: JSONEncoder().encode(state))
        #expect(!restored.eligible(on: day(clock(2 * 86400)), at: clock(2 * 86400)))
        #expect(throws: Error.self) { try state.observe(MischiefClock(date: start, elapsed: -.infinity), previous: nil) }
    }

    @Test func failedRevealCommitRollsBackEntireTransactionAndDoesNotReroll() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repo = try await prepare(url, winning: [day(clock())])
        let original = try await repo.mischiefState()
        let failing = CardRepository(url: url, clock: clock(), beforeCommit: { throw CardStorageError.database(SQLITE_FULL) })
        await #expect(throws: Error.self) { try await bonus(failing, at: clock()) }
        #expect(try await repo.mischiefState() == original)
        await #expect(throws: Error.self) { try await failing.setMischiefEnabled(false, clock: clock()) }
        #expect(try await repo.mischiefState() == original)
        #expect(try await repo.retainedBonus(on: day(clock())) == nil)
        await #expect(throws: Error.self) {
            try await repo.bonus(on: day(clock()), today: today(), candidates: DailyContentProvider().bonusCandidates,
                                 clock: clock(), shadow: { throw CardStorageError.unavailable })
        }
        #expect(try await repo.mischiefState() == original)
        #expect(try await bonus(repo, at: clock()).snapshot.cardID == ShadowLordCard.card.id)
    }

    @Test func queuedMidnightRequestNeverConsumesRareRevealOrCooldown() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repo = try await prepare(url, winning: [day(clock())])
        let selected = try await repo.bonus(on: day(clock()), today: today(),
            candidates: DailyContentProvider().bonusCandidates, clock: clock(86400))
        #expect(selected.snapshot.cardID != ShadowLordCard.card.id)
        #expect(try await repo.mischiefState().lastReveal == nil)
    }

    @Test func queuedOlderObservationDoesNotTurnWinningDayIntoOrdinary() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repo = try await prepare(url, winning: [day(clock())])
        try await repo.observeMischiefClock(clock(1))
        try await repo.observeMischiefClock(clock())
        let selected = try await bonus(repo, at: clock())
        #expect(selected.snapshot.cardID == ShadowLordCard.card.id)
        #expect(try await repo.mischiefState().lastReveal == clock(1).date)
    }

    @Test func retainedReadsCannotEraseForwardJumpEvidenceAfterRelaunch() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repo = try await prepare(url, winning: [day(clock())])
        _ = try await bonus(repo, at: clock())
        let relaunched = CardRepository(url: url, clock: clock(86400))
        let jumped = MischiefClock(date: clock(30 * 86400).date, elapsed: clock(86400).elapsed + 1)
        _ = try await relaunched.bonus(on: day(clock()), today: today(), candidates: [], clock: jumped)
        let result = try await bonus(relaunched, at: jumped)
        #expect(result.snapshot.cardID != ShadowLordCard.card.id)
        #expect(try await relaunched.mischiefState().blockedUntil == jumped.date.addingTimeInterval(MischiefState.cooldown))
        #expect(try await relaunched.mischiefState().lastReveal == start)
    }

    @Test func concurrentRequestsKeepOneRevealAndGuestSettingSurvivesAccountStates() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = try await prepare(url, winning: [day(clock())])
        let other = CardRepository(url: url, clock: clock())
        let today = try today(), time = clock(), date = day(time), candidates = DailyContentProvider().bonusCandidates
        async let a = first.bonus(on: date, today: today, candidates: candidates, clock: time)
        async let b = other.bonus(on: date, today: today, candidates: candidates, clock: time)
        let pair = try await (a, b)
        #expect(pair.0.snapshot == pair.1.snapshot)
        #expect(try await first.mischiefState().lastReveal == time.date)
        for auth in [AppRouter.AuthState.loading, .signedOut, .signedIn(uid: "local-test")] {
            #expect(SettingsSheet.mischief.isAvailable(for: auth))
            #expect(!SettingsSheet.mischief.shouldDismiss(from: auth, to: .signedOut))
        }
        #expect(try await other.mischiefState().enabled)
    }

    @Test func v1MigrationAndCorruptPolicyPreserveExistingCards() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repo = CardRepository(url: url, clock: clock())
        let ordinary = try await bonus(repo, at: clock())
        try await repo.save(ordinary)
        try sql(url, "DROP TABLE mischief_state; PRAGMA user_version=1")
        let migrated = CardRepository(url: url)
        #expect(try await migrated.mischiefState().enabled == false)
        #expect(try await migrated.load(ordinary.snapshot.id).artwork == ordinary.artwork)
        try sql(url, "UPDATE mischief_state SET state=x'7b'")
        #expect(try await migrated.retainedBonus(on: day(clock()))?.snapshot == ordinary.snapshot)
        await #expect(throws: Error.self) { try await migrated.setMischiefEnabled(true, clock: clock()) }
        await #expect(throws: Error.self) { try await bonus(migrated, at: clock(86400)) }
        try sql(url, "DELETE FROM mischief_state")
        await #expect(throws: Error.self) { try await CardRepository(url: url).mischiefState() }
        #expect(try await migrated.favorites().map(\.id) == [ordinary.snapshot.id])
    }
}
