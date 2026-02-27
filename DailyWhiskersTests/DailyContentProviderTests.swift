import Foundation
import Testing
@testable import DailyWhiskers

@Suite("Daily Content Provider")
struct DailyContentProviderTests {
    @Test("Decodes manifest JSON and keeps valid card")
    func decodeManifestJSON() throws {
        let json = """
        {
          "cards": [
            {
              "id": "valid_card",
              "archetype": "celestial",
              "imageName": "celestial_constellation_watcher",
              "quote": "Test quote",
              "vibe": "calm"
            }
          ]
        }
        """

        let data = Data(json.utf8)
        let manifest = DailyContentProvider.manifest(
            from: data,
            bundle: .main,
            imageResolver: { _ in true }
        )

        #expect(manifest.cards.count == 1)
        #expect(manifest.cards[0].id == "valid_card")
        #expect(manifest.cards[0].imageName == "celestial_constellation_watcher")
    }

    @Test("Deterministic daily selection uses YYYYMMDD modulo count")
    func deterministicSelection() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let cards = [
            DailyCard(id: "card_0", archetype: "cozy", imageName: "img_0", quote: "q0", vibe: nil),
            DailyCard(id: "card_1", archetype: "cozy", imageName: "img_1", quote: "q1", vibe: nil),
            DailyCard(id: "card_2", archetype: "cozy", imageName: "img_2", quote: "q2", vibe: nil)
        ]
        let provider = DailyContentProvider(calendar: calendar, manifest: DailyContentManifest(cards: cards))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 2, day: 27, hour: 12)))

        let selected = try #require(provider.content(for: date))
        let expectedIndex = 20260227 % cards.count

        #expect(selected.id == cards[expectedIndex].id)
    }

    @Test("Invalid JSON falls back to built-in fallback card")
    func invalidJSONFallsBack() {
        let data = Data("not-json".utf8)
        let manifest = DailyContentProvider.manifest(
            from: data,
            bundle: .main,
            imageResolver: { _ in true }
        )

        #expect(manifest.cards.count == 1)
        #expect(manifest.cards[0].id == DailyContentProvider.fallbackCard.id)
    }

    @Test("Rollover expectations: same day is stable, next day updates identifier")
    func rolloverExpectations() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let cards = [
            DailyCard(id: "card_0", archetype: "cozy", imageName: "img_0", quote: "q0", vibe: nil),
            DailyCard(id: "card_1", archetype: "cozy", imageName: "img_1", quote: "q1", vibe: nil)
        ]
        let provider = DailyContentProvider(calendar: calendar, manifest: DailyContentManifest(cards: cards))

        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 9)))
        let evening = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 21)))
        let nextDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 9)))

        let morningIdentifier = provider.dayIdentifier(for: morning)
        let eveningIdentifier = provider.dayIdentifier(for: evening)
        let nextDayIdentifier = provider.dayIdentifier(for: nextDay)

        let morningCard = try #require(provider.content(for: morning))
        let eveningCard = try #require(provider.content(for: evening))

        #expect(morningIdentifier == eveningIdentifier)
        #expect(nextDayIdentifier != morningIdentifier)
        #expect(morningCard.id == eveningCard.id)
    }

    @Test("Cards with missing image assets are dropped during validation")
    func missingImageCardIsDropped() {
        let json = """
        {
          "cards": [
            {
              "id": "valid_card",
              "archetype": "cozy",
              "imageName": "present_image",
              "quote": "Valid quote"
            },
            {
              "id": "missing_image_card",
              "archetype": "cozy",
              "imageName": "missing_image",
              "quote": "Should be dropped"
            }
          ]
        }
        """

        let data = Data(json.utf8)
        let manifest = DailyContentProvider.manifest(
            from: data,
            imageResolver: { imageName in
                imageName != "missing_image"
            }
        )

        #expect(manifest.cards.count == 1)
        #expect(manifest.cards[0].id == "valid_card")
    }
}
