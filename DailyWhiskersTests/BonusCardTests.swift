import Testing
import UIKit
import SQLite3
@testable import DailyWhiskers

@Suite("One retained bonus per local date", .serialized)
@MainActor
struct BonusCardTests {
    private func url() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("cards.sqlite") }
    private func day(_ value: String, zone: String = "UTC") -> BonusDay {
        BonusDay(date: ISO8601DateFormatter().date(from: value)!, timeZone: TimeZone(identifier: zone)!)
    }
    private func card(_ n: Int, quote: String? = nil) -> DailyCard {
        DailyCard(id: "cat-\(n)", archetype: "cozy", imageName: "\(n)", quote: quote ?? "Quote \(n)", vibe: "calm")
    }
    private nonisolated func artwork(_ card: DailyCard) throws -> Data {
        let n = Int(card.imageName) ?? 0
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return try #require(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 12), format: format).image { c in
            UIColor(hue: CGFloat(n) / 40, saturation: 1, brightness: 1, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 0, width: 8, height: 12))
        }.pngData())
    }
    private func today() throws -> RetainedCard { try CardSnapshot.capture(card: card(0), artwork: artwork(card(0))) }
    private func sql(_ url: URL, _ statement: String) throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK); defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK)
    }

    @Test("Ordinary Bonus draw, save, reopen and share each new card", arguments: [
        ("2026-01-09", "cozy_theo_lookout", "There’s a whole world on the other side of a quiet moment.", true),
        ("2026-01-13", "forest_theo_little_adventurer", "Even a small adventure counts.", true),
        ("2026-01-17", "celestial_theo_starlight_nap", "Some warmth stays long after the sun goes down.", true),
        ("2026-02-07", "alchemy_lantern_apothecary", "Small things can change the whole mixture.", false),
        ("2026-02-23", "noble_after_the_rain", "You can be steady without standing still.", false)
    ])
    func ordinaryBonusRoundTrip(dayKey: String, id: String, quote: String, isTribute: Bool) async throws {
        let path = url()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let provider = DailyContentProvider(calendar: calendar)
        let date = try #require(ISO8601DateFormatter().date(from: dayKey + "T12:00:00Z"))
        let repo = CardRepository(url: path)
        let todayCard = try #require(provider.content(for: date))
        let selected = try await repo.bonus(on: BonusDay(date: date, timeZone: calendar.timeZone),
            today: repo.capture(todayCard), candidates: provider.bonusCandidates)
        let dedication = isTribute ? "In memory of Theo" : nil
        #expect(selected.snapshot.cardID == id)
        #expect(selected.snapshot.quote == quote)
        #expect(selected.snapshot.dedication == dedication)
        #expect(selected.snapshot.vibe == nil)
        #expect(selected.snapshot.schemaVersion == (isTribute ? 2 : 1))
        try await repo.save(selected)
        let loaded = try await CardRepository(url: path).load(selected.snapshot.id)
        #expect(loaded.snapshot == selected.snapshot)
        #expect(loaded.artwork == selected.artwork)
        let export = try DailyCardShareRenderer.render(DailyCardShareSnapshot(retained: loaded))
        #expect(export.text == ["“\(quote)”", dedication, "Daily Whiskers"].compactMap { $0 }.joined(separator: "\n\n"))
        #expect(export.image.size.width == DailyCardShareRenderer.width)
        #expect(export.image.size.height <= DailyCardShareRenderer.maximumHeight)
        if isTribute {
            var plain = try #require(provider.bonusCandidates.first { $0.id == id })
            plain.dedication = nil
            let other = try CardSnapshot.capture(card: plain, artwork: loaded.artwork)
            let plainExport = try DailyCardShareRenderer.render(DailyCardShareSnapshot(retained: other))
            #expect(other.snapshot.id != loaded.snapshot.id)
            #expect(plainExport.image.size.height < export.image.size.height)
        }
    }

    @Test func localMidnightTravelDSTAndRepeatedDates() {
        let before = day("2026-10-19T23:59:59Z")
        #expect(before.key == "2026-10-19")
        #expect(day("2026-10-20T00:00:00Z").key == "2026-10-20")
        #expect(day("2026-10-20T02:00:00Z", zone: "America/Los_Angeles").key == before.key)
        #expect(day("2026-11-01T05:30:00Z", zone: "America/New_York").key == day("2026-11-01T06:30:00Z", zone: "America/New_York").key)
        #expect(day("2026-03-08T06:59:59Z", zone: "America/New_York").key == day("2026-03-08T07:00:00Z", zone: "America/New_York").key)
        #expect(day("2026-10-19T12:00:00Z", zone: "Pacific/Kiritimati").key == "2026-10-20")
    }

    @Test func persistedAcrossRelaunchTravelPackChangesFavoritesClearAndBackup() async throws {
        let path = url(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let repo = CardRepository(url: path), originalToday = try today()
        let first = try await repo.bonus(on: day("2026-10-19T12:00:00Z"), today: originalToday, candidates: [card(1)], artwork: artwork)
        try await repo.save(first)
        try await repo.clearFavorites()
        let reopened = CardRepository(url: path)
        let revisited = try await reopened.bonus(on: day("2026-10-20T02:00:00Z", zone: "America/Los_Angeles"), today: originalToday, candidates: [], artwork: { _ in throw BonusCardError.noDistinctContent })
        #expect(first.snapshot == revisited.snapshot); #expect(first.artwork == revisited.artwork)
        #expect(try await reopened.favorites().isEmpty)
        let next = try await reopened.bonus(on: day("2026-10-20T12:00:00Z"), today: originalToday, candidates: [card(2)], artwork: artwork)
        #expect(next.snapshot.id != first.snapshot.id)
        let backwards = try await reopened.bonus(on: day("2026-10-19T12:00:00Z"), today: originalToday, candidates: [card(3)], artwork: artwork)
        #expect(backwards.snapshot == first.snapshot)
        try await reopened.save(backwards)
        #expect(try await reopened.load(first.snapshot.id).artwork == first.artwork)
        let backup = path.deletingLastPathComponent().appendingPathComponent("backup.sqlite")
        try await reopened.backup(to: backup)
        let restored = try await CardRepository(url: backup).bonus(on: day("2026-10-19T12:00:00Z"), today: originalToday, candidates: [], artwork: artwork)
        #expect(restored.snapshot == first.snapshot)
        let export = try DailyCardShareRenderer.render(DailyCardShareSnapshot(retained: restored))
        #expect(export.text.contains(first.snapshot.quote))
    }

    @Test func excludesTodayQuotePixelsAndInvalidContentWithoutSpendingAllowance() async throws {
        let path = url(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let repo = CardRepository(url: path), today = try today(), date = day("2026-10-19T12:00:00Z")
        let duplicateArt = DailyCard(id: "another-id", archetype: "cozy", imageName: "0", quote: "Another quote", vibe: nil)
        let invalid = card(4, quote: "   ")
        await #expect(throws: Error.self) {
            try await repo.bonus(on: date, today: today, candidates: [card(0), card(1, quote: today.snapshot.quote), duplicateArt, invalid], artwork: artwork)
        }
        await #expect(throws: Error.self) {
            try await repo.bonus(on: date, today: today, candidates: [card(3)], artwork: { _ in Data([0, 1]) })
        }
        let selected = try await repo.bonus(on: date, today: today, candidates: [card(2)], artwork: artwork)
        #expect(selected.snapshot.cardID == "cat-2")
        #expect(selected.snapshot.artworkPixelDigest != today.snapshot.artworkPixelDigest)
        #expect(selected.snapshot.quote != today.snapshot.quote)
    }

    @Test func avoidsSevenMostRecentlyIssuedCardsAndAllowsSmallPoolFallback() async throws {
        let path = url(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let repo = CardRepository(url: path), today = try today()
        for n in 1...7 {
            _ = try await repo.bonus(on: day(String(format: "2026-10-%02dT12:00:00Z", n)), today: today, candidates: [card(n)], artwork: artwork)
        }
        let chosen = try await repo.bonus(on: day("2026-10-08T12:00:00Z"), today: today, candidates: (1...8).map { card($0) }, artwork: artwork)
        #expect(chosen.snapshot.cardID == "cat-8")
        // Reopening an old date does not move it to the newest position.
        _ = try await repo.bonus(on: day("2026-10-01T12:00:00Z"), today: today, candidates: [], artwork: artwork)
        let oldest = try await repo.bonus(on: day("2026-10-09T12:00:00Z"), today: today, candidates: (1...8).map { card($0) }, artwork: artwork)
        #expect(oldest.snapshot.cardID == "cat-1")
        let small = try await repo.bonus(on: day("2026-10-10T12:00:00Z"), today: today, candidates: [card(1)], artwork: artwork)
        #expect(small.snapshot.cardID == "cat-1")
    }

    @Test func retainedLookupNeedsNeitherTodayNorCurrentPackAndDoesNotSpendAllowance() async throws {
        let path = url(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let repo = CardRepository(url: path), date = day("2026-10-19T12:00:00Z")
        #expect(try await repo.retainedBonus(on: date) == nil)
        let selected = try await repo.bonus(on: date, today: today(), candidates: [card(1)], artwork: artwork)
        let reopened = CardRepository(url: path)
        let retained = try #require(await reopened.retainedBonus(on: date))
        #expect(retained.snapshot == selected.snapshot)
        #expect(retained.artwork == selected.artwork)
        #expect(try await reopened.retainedBonus(on: day("2026-10-20T12:00:00Z")) == nil)
        try sql(path, "UPDATE snapshot SET metadata=x'7b'")
        await #expect(throws: Error.self) { try await reopened.retainedBonus(on: date) }
    }

    @Test func corruptRecencyMetadataDoesNotBlockFutureDatesOrRerollOriginalDate() async throws {
        let path = url(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let repo = CardRepository(url: path), today = try today(), originalDate = day("2026-10-19T12:00:00Z")
        _ = try await repo.bonus(on: day("2026-10-18T12:00:00Z"), today: today, candidates: [card(2)], artwork: artwork)
        let original = try await repo.bonus(on: originalDate, today: today, candidates: [card(1)], artwork: artwork)
        try sql(path, "UPDATE snapshot SET metadata=x'7b' WHERE id='\(original.snapshot.id)'")
        await #expect(throws: Error.self) { try await repo.bonus(on: originalDate, today: today, candidates: [card(3)], artwork: artwork) }
        let nextDate = day("2026-10-20T12:00:00Z")
        let selected = try await repo.bonus(on: nextDate, today: today, candidates: [card(1), card(2), card(3)], artwork: artwork)
        // Skip the damaged version and still honor the readable recent card.
        #expect(selected.snapshot.cardID == "cat-3")
        try await repo.clearFavorites()
        let reopened = CardRepository(url: path)
        let retained = try #require(await reopened.retainedBonus(on: nextDate))
        #expect(retained.snapshot == selected.snapshot); #expect(retained.artwork == selected.artwork)
        await #expect(throws: Error.self) { try await reopened.retainedBonus(on: originalDate) }
        let later = try await reopened.bonus(on: day("2026-10-21T12:00:00Z"), today: today, candidates: [card(4)], artwork: artwork)
        #expect(later.snapshot.cardID == "cat-4")
    }

    @Test func failedCommitKeepsAllowanceAndCorruptPersistedCardNeverRerolls() async throws {
        let path = url(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let repo = CardRepository(url: path), today = try today(), date = day("2026-10-19T12:00:00Z")
        _ = try await repo.favorites() // create schema before injecting transaction failure
        let failing = CardRepository(url: path, beforeCommit: { throw CardStorageError.database(SQLITE_FULL) })
        await #expect(throws: Error.self) { try await failing.bonus(on: date, today: today, candidates: [card(1)], artwork: artwork) }
        let selected = try await repo.bonus(on: date, today: today, candidates: [card(2)], artwork: artwork)
        #expect(selected.snapshot.cardID == "cat-2")
        try sql(path, "UPDATE artwork SET bytes=x'0102'")
        await #expect(throws: Error.self) { try await repo.bonus(on: date, today: today, candidates: [card(3)], artwork: artwork) }
        try sql(path, "DELETE FROM artwork")
        await #expect(throws: Error.self) { try await repo.bonus(on: date, today: today, candidates: [card(3)], artwork: artwork) }
    }
}
