import Foundation

struct DailyCard: Decodable, Sendable, Equatable {
    let id: String
    let archetype: String
    let imageName: String
    let quote: String
    let vibe: String?
    var dedication: String?
}

struct DailyContentManifest: Decodable {
    let cards: [DailyCard]
    var bonusOnlyCards: [DailyCard]?

    var bonusCandidates: [DailyCard] { cards + (bonusOnlyCards ?? []) }
}
