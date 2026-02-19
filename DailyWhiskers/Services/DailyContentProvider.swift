import Foundation

struct DailyContentProvider {
    private let calendar: Calendar
    private let manifest: DailyContentManifest

    init(calendar: Calendar = .current, bundle: Bundle = .main) {
        self.calendar = calendar
        self.manifest = Self.loadManifest(from: bundle)
    }

    func contentForToday() -> DailyWhiskerEntry? {
        guard !manifest.quotes.isEmpty, !manifest.imageNames.isEmpty else {
            return nil
        }

        let seed = daySeed(for: Date())
        let quote = manifest.quotes[seed % manifest.quotes.count]
        let imageName = manifest.imageNames[seed % manifest.imageNames.count]
        return DailyWhiskerEntry(quote: quote, imageName: imageName)
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
            return DailyContentManifest(quotes: [], imageNames: [])
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(DailyContentManifest.self, from: data)
        } catch {
            return DailyContentManifest(quotes: [], imageNames: [])
        }
    }
}
