import Foundation
import CryptoKit

/// Separate from the ordinary manifest: this content can never replace Today.
enum ShadowLordCard {
    static let card = DailyCard(id: "shadow-lord", archetype: "Shadow Lord", imageName: "shadow-lord-original",
                               quote: "Today we conquer our enemies. After a nap.", vibe: nil)
    static let artworkChecksum = "25f562eedfa5410fa481160051ac4924eab9d688aec68a4c996e8dff30184c91"

    static func capture() throws -> RetainedCard {
        let bytes = try BundledCardArtwork.bytes(for: card)
        guard ArtworkIdentity.checksum(bytes) == artworkChecksum else { throw CardStorageError.unavailable }
        return try CardSnapshot.capture(card: card, artwork: bytes)
    }
}

struct MischiefClock: Equatable, Sendable {
    let date: Date
    let elapsed: TimeInterval

    private static let origin = ContinuousClock.now
    static func now() -> Self {
        let duration = origin.duration(to: .now).components
        return Self(date: Date(), elapsed: Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
    }
}

/// Versioned installation-owned state, committed with the Bonus ledger. Never reset on opt-out.
struct MischiefState: Codable, Equatable, Sendable {
    static let cooldown: TimeInterval = 14 * 24 * 60 * 60
    var version = 1
    var enabled = false
    var seed = UUID().uuidString
    var latestDay: String?
    var highWater: Date?
    var lastReveal: Date?
    var blockedUntil: Date?

    func validate() throws {
        guard version == 1, !seed.isEmpty,
              [highWater, lastReveal, blockedUntil].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              lastReveal == nil || (highWater != nil && lastReveal! <= highWater!),
              latestDay.map({ $0.count == 10 && $0.filter(\.isNumber).count == 8 }) ?? true
        else { throw CardStorageError.unavailable }
    }

    /// Domain-separated, stable per installation and local date. Rejection sampling
    /// avoids modulo bias: exactly one of ten equiprobable buckets is selected.
    static func selected(seed: String, day: String) -> Bool {
        var round = 0
        while true {
            let digest = SHA256.hash(data: Data("DWMischief-v1:\(seed.count):\(seed):\(day):\(round)".utf8))
            if let byte = digest.first(where: { $0 < 250 }) { return byte % 10 == 0 }
            round += 1
        }
    }

    /// Observe before testing eligibility, even while disabled. A rollback freezes
    /// new reveals until the high-water date is reached. A detected forward jump
    /// requires another full cooldown; a timezone change never advances elapsed time.
    mutating func observe(_ clock: MischiefClock, previous: MischiefClock?) throws {
        guard clock.date.timeIntervalSince1970.isFinite, clock.elapsed.isFinite, clock.elapsed >= 0 else { throw CardStorageError.unavailable }
        if let previous, clock.elapsed >= previous.elapsed {
            let wall = clock.date.timeIntervalSince(previous.date)
            let monotonic = clock.elapsed - previous.elapsed
            if wall - monotonic > 300 {
                blockedUntil = max(blockedUntil ?? .distantPast, clock.date.addingTimeInterval(Self.cooldown))
            }
        }
        highWater = max(highWater ?? .distantPast, clock.date)
    }

    func eligible(on day: BonusDay, at clock: MischiefClock) -> Bool {
        guard let zone = TimeZone(identifier: day.timeZone),
              BonusDay(date: clock.date, timeZone: zone).key == day.key else { return false }
        return enabled && clock.date >= (highWater ?? .distantPast) &&
        clock.date >= (blockedUntil ?? .distantPast) &&
        (latestDay.map({ day.key > $0 }) ?? true) &&
        (lastReveal.map({ clock.date.timeIntervalSince($0) >= Self.cooldown }) ?? true)
    }
}
