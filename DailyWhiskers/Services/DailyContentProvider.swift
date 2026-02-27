import Foundation
#if canImport(UIKit)
import UIKit
#endif
import os

struct DailyContentProvider {
    private let calendar: Calendar
    private let manifest: DailyContentManifest
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DailyWhiskers",
        category: "DailyContentProvider"
    )
    private static let fallbackCard = DailyCard(
        id: "fallback_celestial_constellation_watcher",
        archetype: "celestial",
        imageName: "celestial_constellation_watcher",
        quote: "You are part of something beautifully vast.",
        vibe: "vast"
    )

    init(calendar: Calendar = .current, bundle: Bundle = .main) {
        self.calendar = calendar
        self.manifest = Self.loadManifest(from: bundle)
    }

    func contentForToday() -> DailyCard? {
        guard !manifest.cards.isEmpty else {
            Self.logger.error("Manifest unexpectedly empty after load; using fallback card.")
            return Self.fallbackCard
        }

        let seed = daySeed(for: Date())
        return manifest.cards[seed % manifest.cards.count]
    }

    private func daySeed(for date: Date) -> Int {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let year = comps.year ?? 1970
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        return year * 10_000 + month * 100 + day
    }

    private static func loadManifest(from bundle: Bundle) -> DailyContentManifest {
        guard let url = bundle.url(forResource: "daily_whiskers_content", withExtension: "json") else {
            logger.error("Missing daily_whiskers_content.json in bundle; using fallback card.")
            return DailyContentManifest(cards: [fallbackCard])
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(DailyContentManifest.self, from: data)
            let validatedCards = validateManifestCards(decoded.cards, bundle: bundle)
            if validatedCards.isEmpty {
                logger.error("No valid cards after manifest validation; using fallback card.")
                return DailyContentManifest(cards: [fallbackCard])
            }
            return DailyContentManifest(cards: validatedCards)
        } catch {
            logger.error("Failed to decode daily_whiskers_content.json: \(error.localizedDescription, privacy: .public). Using fallback card.")
            return DailyContentManifest(cards: [fallbackCard])
        }
    }

    private static func validateManifestCards(_ cards: [DailyCard], bundle: Bundle) -> [DailyCard] {
        var seenIDs = Set<String>()
        var validCards: [DailyCard] = []

        for (index, card) in cards.enumerated() {
            let normalizedCard = DailyCard(
                id: card.id.trimmingCharacters(in: .whitespacesAndNewlines),
                archetype: card.archetype.trimmingCharacters(in: .whitespacesAndNewlines),
                imageName: card.imageName.trimmingCharacters(in: .whitespacesAndNewlines),
                quote: card.quote.trimmingCharacters(in: .whitespacesAndNewlines),
                vibe: card.vibe?.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            guard !normalizedCard.id.isEmpty else {
                logger.error("Invalid card at index \(index): empty id. Card was dropped.")
                continue
            }

            guard !normalizedCard.archetype.isEmpty else {
                logger.error("Invalid card id \(normalizedCard.id, privacy: .public): empty archetype. Card was dropped.")
                continue
            }

            guard !normalizedCard.imageName.isEmpty else {
                logger.error("Invalid card id \(normalizedCard.id, privacy: .public): empty imageName. Card was dropped.")
                continue
            }

            guard !normalizedCard.quote.isEmpty else {
                logger.error("Invalid card id \(normalizedCard.id, privacy: .public): empty quote. Card was dropped.")
                continue
            }

            guard hasImageNamed(normalizedCard.imageName, in: bundle) else {
                logger.error("Card id \(normalizedCard.id, privacy: .public) references missing image asset \(normalizedCard.imageName, privacy: .public). Card was dropped.")
                continue
            }

            guard seenIDs.insert(normalizedCard.id).inserted else {
                logger.error("Duplicate card id \(normalizedCard.id, privacy: .public) detected. Card was dropped.")
                continue
            }

            let vibe = normalizedCard.vibe.flatMap { value in
                value.isEmpty ? nil : value
            }

            validCards.append(
                DailyCard(
                    id: normalizedCard.id,
                    archetype: normalizedCard.archetype,
                    imageName: normalizedCard.imageName,
                    quote: normalizedCard.quote,
                    vibe: vibe
                )
            )
        }

        if validCards.count != cards.count {
            logger.notice(
                "Validated manifest cards: kept \(validCards.count), dropped \(cards.count - validCards.count)."
            )
        }

        return validCards
    }

    private static func hasImageNamed(_ imageName: String, in bundle: Bundle) -> Bool {
        #if canImport(UIKit)
        UIImage(named: imageName, in: bundle, compatibleWith: nil) != nil
        #else
        true
        #endif
    }
}
