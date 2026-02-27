import SwiftUI

struct DailyWhiskersView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    private let provider = DailyContentProvider()

    @State private var currentCard: DailyCard?
    @State private var currentDayIdentifier: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                if let entry = currentCard {
                    DailyRitualCardView(
                        data: DailyCardData(
                            archetype: entry.archetype,
                            imageName: entry.imageName,
                            quote: entry.quote,
                            vibe: entry.vibe ?? ""
                        )
                    )
                } else {
                    ZStack {
                        Color(.systemGroupedBackground).ignoresSafeArea()
                        Text("No daily content found.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear {
                refreshDailyContentIfNeeded(force: true)
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                refreshDailyContentIfNeeded(force: false)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Log Out", role: .destructive) {
                            do {
                                try router.signOut()
                            } catch {
                                // Keep UI minimal for v1.
                            }
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func refreshDailyContentIfNeeded(force: Bool) {
        let todayIdentifier = provider.dayIdentifier(for: Date())

        guard force || currentDayIdentifier != todayIdentifier else {
            return
        }

        currentCard = provider.content(for: Date())
        currentDayIdentifier = todayIdentifier
    }
}

