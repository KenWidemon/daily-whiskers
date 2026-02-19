import Foundation

struct DailyQuote: Decodable {
    let text: String
    let vibe: String?
}

struct DailyContentManifest: Decodable {
    let quotes: [DailyQuote]
    let imageNames: [String]
}

struct DailyWhiskerEntry {
    let quote: DailyQuote
    let imageName: String
}
