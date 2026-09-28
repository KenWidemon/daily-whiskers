import Foundation
import SwiftUI
import Testing
import UIKit
@testable import DailyWhiskers

@Suite("Content integrity")
struct DailyContentIntegrityTests {
    private func card(_ id: String = "valid") -> [String: String] {
        ["id": id, "archetype": "cozy", "imageName": "cat", "quote": "Be still."]
    }

    private func load(_ cards: [[String: String]]) throws -> DailyContentManifest {
        let data = try JSONSerialization.data(withJSONObject: ["cards": cards])
        return DailyContentProvider.manifest(from: data, imageResolver: { $0 == "cat" })
    }

    @Test("Empty JSON manifest uses the fallback")
    func emptyManifest() throws {
        #expect(try load([]).cards.map(\.id) == [DailyContentProvider.fallbackCard.id])
    }

    @Test("Empty injected manifest still selects a fallback")
    func emptyInjectedManifest() {
        let provider = DailyContentProvider(manifest: DailyContentManifest(cards: []))
        #expect(provider.content(for: Date(timeIntervalSince1970: 0))?.id == DailyContentProvider.fallbackCard.id)
    }

    @Test("Blank required fields drop only the invalid card", arguments: ["id", "archetype", "imageName", "quote"])
    func blankRequiredField(_ field: String) throws {
        var invalid = card("invalid")
        invalid[field] = " \n\t "
        #expect(try load([invalid, card()]).cards.map(\.id) == ["valid"])
    }

    @Test("Missing required keys cause decode fallback", arguments: ["id", "archetype", "imageName", "quote"])
    func missingRequiredKey(_ field: String) throws {
        var invalid = card()
        invalid.removeValue(forKey: field)
        #expect(try load([invalid]).cards.map(\.id) == [DailyContentProvider.fallbackCard.id])
    }

    @Test("All invalid cards use fallback")
    func allInvalid() throws {
        var blank = card("blank")
        blank["quote"] = " "
        var missingImage = card("missing")
        missingImage["imageName"] = "absent"
        #expect(try load([blank, missingImage]).cards.map(\.id) == [DailyContentProvider.fallbackCard.id])
    }

    @Test("Duplicates keep the first valid card after trimming IDs")
    func duplicateIDs() throws {
        var duplicate = card(" valid ")
        duplicate["quote"] = "Later duplicate"
        let cards = try load([card(), duplicate, card("other")]).cards
        #expect(cards.map(\.id) == ["valid", "other"])
        #expect(cards.first?.quote == "Be still.")
    }

    @Test("An invalid card does not reserve its ID")
    func invalidDuplicatePrecedesValid() throws {
        var invalid = card()
        invalid["imageName"] = "absent"
        #expect(try load([invalid, card()]).cards.map(\.id) == ["valid"])
    }

    @Test("Fields are trimmed and blank vibes become nil")
    func normalization() throws {
        var padded = card().mapValues { " \n\($0)\t " }
        padded["vibe"] = " \n "
        let result = try #require(load([padded]).cards.first)
        #expect(result.id == "valid")
        #expect(result.archetype == "cozy")
        #expect(result.imageName == "cat")
        #expect(result.quote == "Be still.")
        #expect(result.vibe == nil)
    }

    @Test("Every bundled card and fallback image passes real asset validation")
    func bundledContent() throws {
        let url = try #require(Bundle.main.url(forResource: "daily_whiskers_content", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(DailyContentManifest.self, from: data)
        #expect(!decoded.cards.isEmpty)
        let validated = DailyContentProvider.manifest(from: data)
        #expect(validated.cards.map(\.id) == decoded.cards.map(\.id))
        #expect(UIImage(named: DailyContentProvider.fallbackCard.imageName) != nil)
    }
}

@Suite("Daily selection and foreground refresh")
struct DailyContentRefreshTests {
    private let cards = (0..<7).map {
        DailyCard(id: "card_\($0)", archetype: "cozy", imageName: "cat", quote: "Quote \($0)", vibe: nil)
    }

    private func provider(in zone: String = "UTC") throws -> DailyContentProvider {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return DailyContentProvider(calendar: calendar, manifest: DailyContentManifest(cards: cards))
    }

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    @Test("Foreground refresh crosses calendar boundaries", arguments: [
        ("2026-01-31T23:59:59Z", "2026-02-01T00:00:00Z", 20260131, 20260201),
        ("2026-12-31T23:59:59Z", "2027-01-01T00:00:00Z", 20261231, 20270101),
        ("2028-02-28T23:59:59Z", "2028-02-29T00:00:00Z", 20280228, 20280229),
        ("2028-02-29T23:59:59Z", "2028-03-01T00:00:00Z", 20280229, 20280301)
    ])
    func boundary(_ before: String, _ after: String, _ oldDay: Int, _ newDay: Int) throws {
        var state = DailyContentState(provider: try provider())
        state.refresh(at: try date(before), force: true)
        #expect(state.currentDayIdentifier == oldDay)
        #expect(state.currentCard?.id == cards[oldDay % cards.count].id)
        state.scenePhaseDidChange(to: .active, at: try date(after))
        #expect(state.currentDayIdentifier == newDay)
        #expect(state.currentCard?.id == cards[newDay % cards.count].id)
    }

    @Test("Inactive and background events preserve the displayed day")
    func backgroundThenForeground() throws {
        var state = DailyContentState(provider: try provider())
        state.refresh(at: try date("2026-09-05T12:00:00Z"), force: true)
        let originalID = state.currentCard?.id
        for phase in [ScenePhase.inactive, .background] {
            state.scenePhaseDidChange(to: phase, at: try date("2026-09-06T12:00:00Z"))
            #expect(state.currentDayIdentifier == 20260905)
            #expect(state.currentCard?.id == originalID)
        }
        state.scenePhaseDidChange(to: .active, at: try date("2026-09-06T12:00:00Z"))
        #expect(state.currentDayIdentifier == 20260906)
        #expect(state.currentCard?.id == cards[20260906 % cards.count].id)
    }

    @Test("Repeated same-day foreground events keep the card stable")
    func sameDay() throws {
        var state = DailyContentState(provider: try provider())
        #expect(state.currentCard == nil)
        state.scenePhaseDidChange(to: .active, at: try date("2026-09-05T00:00:00Z"))
        let originalID = state.currentCard?.id
        #expect(originalID != nil)
        for _ in 0..<3 {
            state.scenePhaseDidChange(to: .active, at: try date("2026-09-05T23:59:59Z"))
            #expect(state.currentCard?.id == originalID)
            #expect(state.currentDayIdentifier == 20260905)
        }
    }

    @Test("Returning after several days selects today, not the next card")
    func skippedDays() throws {
        var state = DailyContentState(provider: try provider())
        state.refresh(at: try date("2026-09-01T12:00:00Z"))
        state.scenePhaseDidChange(to: .active, at: try date("2026-09-10T12:00:00Z"))
        #expect(state.currentDayIdentifier == 20260910)
        #expect(state.currentCard?.id == cards[20260910 % cards.count].id)
    }

    @Test("The same instant selects by the configured local date", arguments: [
        ("America/Los_Angeles", 20261231), ("UTC", 20270101), ("Asia/Tokyo", 20270101)
    ])
    func localTimeZone(_ zone: String, _ expectedDay: Int) throws {
        let provider = try provider(in: zone)
        let instant = try date("2027-01-01T01:00:00Z")
        #expect(provider.dayIdentifier(for: instant) == expectedDay)
        #expect(provider.content(for: instant)?.id == cards[expectedDay % cards.count].id)
    }

    @Test("DST clock changes do not change the local daily card", arguments: [
        ("2026-03-08T06:59:59Z", "2026-03-08T07:00:00Z", 20260308),
        ("2026-11-01T05:59:59Z", "2026-11-01T06:00:00Z", 20261101)
    ])
    func daylightSaving(_ before: String, _ after: String, _ day: Int) throws {
        var state = DailyContentState(provider: try provider(in: "America/New_York"))
        state.refresh(at: try date(before))
        let originalID = state.currentCard?.id
        state.scenePhaseDidChange(to: .active, at: try date(after))
        #expect(state.currentDayIdentifier == day)
        #expect(state.currentCard?.id == originalID)
    }

    @Test("Foreground rollover follows local midnight, not UTC midnight")
    func localMidnight() throws {
        var state = DailyContentState(provider: try provider(in: "America/New_York"))
        state.refresh(at: try date("2026-09-05T23:59:59Z"))
        let originalID = state.currentCard?.id
        state.scenePhaseDidChange(to: .active, at: try date("2026-09-06T00:00:00Z"))
        #expect(state.currentDayIdentifier == 20260905)
        #expect(state.currentCard?.id == originalID)
        state.scenePhaseDidChange(to: .active, at: try date("2026-09-06T04:00:00Z"))
        #expect(state.currentDayIdentifier == 20260906)
        #expect(state.currentCard?.id == cards[20260906 % cards.count].id)
    }
}
