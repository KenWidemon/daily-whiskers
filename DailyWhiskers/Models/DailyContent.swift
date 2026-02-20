import Foundation

struct DailyCard: Decodable {
    let id: String
    let archetype: String
    let imageName: String
    let quote: String
    let vibe: String?
}

private struct LegacyDailyQuote: Decodable {
    let text: String
    let vibe: String?
}

struct DailyContentManifest: Decodable {
    let cards: [DailyCard]

    init(cards: [DailyCard]) {
        self.cards = cards
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let cards = try container.decodeIfPresent([DailyCard].self, forKey: .cards), !cards.isEmpty {
            self.cards = cards
            return
        }

        let legacyQuotes = try container.decodeIfPresent([LegacyDailyQuote].self, forKey: .quotes) ?? []
        let legacyImageNames = try container.decodeIfPresent([String].self, forKey: .imageNames) ?? []

        guard !legacyQuotes.isEmpty, !legacyImageNames.isEmpty else {
            self.cards = []
            return
        }

        self.cards = legacyQuotes.enumerated().map { index, quote in
            DailyCard(
                id: "legacy_\(index)",
                archetype: "legacy",
                imageName: legacyImageNames[index % legacyImageNames.count],
                quote: quote.text,
                vibe: quote.vibe
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case cards
        case quotes
        case imageNames
    }
}
