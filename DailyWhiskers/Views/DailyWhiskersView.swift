import SwiftUI

struct DailyWhiskersView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    @State private var contentState = DailyContentState()
    @StateObject private var logoutRequest = AuthRequestState()

    var body: some View {
        NavigationStack {
            ZStack {
                if let entry = contentState.currentCard {
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
                contentState.refresh(at: Date(), force: true)
            }
            .onChange(of: scenePhase) { _, newPhase in
                contentState.scenePhaseDidChange(to: newPhase, at: Date())
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Log Out", role: .destructive) {
                            logOut()
                        }
                        .disabled(logoutRequest.isWorking)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens account options, including log out.")
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Couldn't Log Out", isPresented: Binding(
                get: { logoutRequest.errorMessage != nil },
                set: { if !$0 { logoutRequest.errorMessage = nil } }
            )) {
                Button("Try Again") { logOut() }
                Button("Cancel", role: .cancel) { logoutRequest.clearFeedback() }
            } message: {
                Text(logoutRequest.errorMessage ?? "")
            }
        }
    }

    private func logOut() {
        Task {
            await logoutRequest.perform(.logout) {
                try router.signOut()
            }
        }
    }
}

struct DailyContentState {
    private let provider: DailyContentProvider
    private(set) var currentCard: DailyCard?
    private(set) var currentDayIdentifier: Int?

    init(provider: DailyContentProvider = DailyContentProvider()) {
        self.provider = provider
    }

    mutating func scenePhaseDidChange(to phase: ScenePhase, at date: Date) {
        guard phase == .active else { return }
        refresh(at: date)
    }

    mutating func refresh(at date: Date, force: Bool = false) {
        let todayIdentifier = provider.dayIdentifier(for: date)

        guard force || currentDayIdentifier != todayIdentifier else {
            return
        }

        currentCard = provider.content(for: date)
        currentDayIdentifier = todayIdentifier
    }
}
