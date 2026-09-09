import SwiftUI

struct DailyWhiskersView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    @State private var contentState = DailyContentState()
    @StateObject private var accountRequest = AuthRequestState()
    @State private var showingDeletion = false
    @AccessibilityFocusState private var settingsFocused: Bool

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
                        Link("Privacy Policy", destination: AppLinks.privacyPolicy)
                        Link("Support", destination: AppLinks.support)
                        Divider()
                        Button("Log Out", role: .destructive) {
                            logOut()
                        }
                        .disabled(accountRequest.isWorking)
                        Button("Delete Account", role: .destructive) {
                            accountRequest.clearFeedback()
                            showingDeletion = true
                        }
                        .disabled(accountRequest.isWorking)
                    } label: {
                        Image(systemName: "gearshape")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens privacy, support, and account options, including log out and account deletion.")
                    .accessibilityFocused($settingsFocused)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingDeletion, onDismiss: {
                accountRequest.clearFeedback()
                settingsFocused = true
            }) {
                DeleteAccountView(request: accountRequest)
            }
            .alert("Couldn't Log Out", isPresented: Binding(
                get: { !showingDeletion && accountRequest.errorMessage != nil },
                set: { if !$0 { dismissLogoutError() } }
            )) {
                Button("Try Again") { logOut() }
                Button("Cancel", role: .cancel) { dismissLogoutError() }
            } message: {
                Text(accountRequest.errorMessage ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func logOut() {
        Task {
            await accountRequest.perform(.logout) {
                try router.signOut()
            }
        }
    }

    private func dismissLogoutError() {
        accountRequest.clearFeedback()
        settingsFocused = true
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
