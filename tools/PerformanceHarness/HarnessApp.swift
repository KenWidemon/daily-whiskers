import SwiftUI
import os

@main
struct HarnessApp: App {
    var body: some Scene {
        WindowGroup { HarnessView() }
    }
}

private struct HarnessView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var card: DailyCard?
    @State private var isRunning = false
    @State private var status = "Ready: attach Allocations, then start."

    private static let log = OSLog(
        subsystem: "com.example.kenwidemon.dailywhiskers.performanceharness",
        category: .pointsOfInterest
    )

    var body: some View {
        VStack(spacing: 0) {
            if let card {
                DailyRitualCardView(data: DailyCardData(
                    archetype: card.archetype,
                    imageName: card.imageName,
                    quote: card.quote,
                    vibe: card.vibe ?? ""
                ))
            } else {
                Spacer()
            }
            Text(status)
                .font(.caption.monospacedDigit())
                .multilineTextAlignment(.center)
                .padding(8)
            Button("Start Two-Pass Image Check") { isRunning = true }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning || scenePhase != .active)
                .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && isRunning {
                isRunning = false
            }
        }
        .task(id: isRunning) {
            guard isRunning else { return }
            await run()
        }
    }

    @MainActor
    private func run() async {
        os_signpost(.begin, log: Self.log, name: "ImageExercise")
        defer {
            os_signpost(.end, log: Self.log, name: "ImageExercise")
            isRunning = false
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let firstDay = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)) else {
            status = "Invalid fixture date."
            return
        }

        // One real provider per exercise; no Firebase, fake assets, or system clock changes.
        os_signpost(.begin, log: Self.log, name: "ProviderInitialization")
        let provider = DailyContentProvider(calendar: calendar)
        os_signpost(.end, log: Self.log, name: "ProviderInitialization")

        do {
            for pass in 1...2 {
                os_signpost(.begin, log: Self.log, name: "CardPass", "pass=%d", pass)
                do {
                    for day in 0..<31 {
                        try Task.checkCancellation()
                        guard scenePhase == .active else { throw CancellationError() }
                        guard let date = calendar.date(byAdding: .day, value: day, to: firstDay),
                              let nextCard = provider.content(for: date) else {
                            status = "Missing fixture content."
                            os_signpost(.end, log: Self.log, name: "CardPass", "pass=%d incomplete", pass)
                            return
                        }
                        card = nextCard
                        status = "Pass \(pass)/2 - card \(day + 1)/31"
                        os_signpost(.event, log: Self.log, name: "CardSelected",
                                    "pass=%d day=%d image=%{public}@", pass, day + 1, nextCard.imageName)
                        try await Task.sleep(for: .seconds(2))
                    }
                } catch {
                    os_signpost(.end, log: Self.log, name: "CardPass", "pass=%d interrupted", pass)
                    throw error
                }
                os_signpost(.end, log: Self.log, name: "CardPass", "pass=%d", pass)
            }
            status = "Settling for 20 seconds. Leave the card visible."
            os_signpost(.begin, log: Self.log, name: "IdleTail")
            do {
                try await Task.sleep(for: .seconds(20))
            } catch {
                os_signpost(.end, log: Self.log, name: "IdleTail")
                throw error
            }
            os_signpost(.end, log: Self.log, name: "IdleTail")
            guard scenePhase == .active else { throw CancellationError() }
            status = "Complete: two passes and idle tail."
        } catch {
            status = "Interrupted. Relaunch for a fresh-process comparison."
        }
    }
}
