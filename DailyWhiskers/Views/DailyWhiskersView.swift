import SwiftUI

enum AccountSheet: String, Identifiable {
    case signIn, deletion

    var id: String { rawValue }

    func isAvailable(for state: AppRouter.AuthState) -> Bool {
        switch (self, state) {
        case (.signIn, .signedOut), (.deletion, .signedIn): true
        default: false
        }
    }

    func shouldDismiss(from previous: AppRouter.AuthState, to current: AppRouter.AuthState) -> Bool {
        // A deletion form belongs to the identity that opened it, not a later session.
        !isAvailable(for: current) || (self == .deletion && previous != current)
    }
}

struct DailyWhiskersView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    @State private var contentState = DailyContentState()
    @StateObject private var accountRequest = AuthRequestState()
    @StateObject private var deletionRequest = AuthRequestState()
    @State private var accountSheet: AccountSheet?
    @StateObject private var shareState = DailyCardShareState()
    @AccessibilityFocusState private var shareFocused: Bool
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
                    .accessibilityIdentifier("daily-card")
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
                    Button {
                        guard let card = contentState.currentCard else { return }
                        shareFocused = false
                        Task { await shareState.start(card: card) }
                    } label: {
                        Group {
                            if shareState.isRendering {
                                ProgressView()
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(contentState.currentCard == nil || accountSheet != nil || shareState.isRendering || shareState.export != nil)
                    .accessibilityLabel(shareState.isRendering ? "Preparing Card" : "Share Today's Card")
                    .accessibilityHint("Shares the artwork and quote. You choose where to send it.")
                    .accessibilityIdentifier("share-daily-card")
                    .accessibilityFocused($shareFocused)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Link("Privacy Policy", destination: AppLinks.privacyPolicy)
                        Link("Support", destination: AppLinks.support)
                        Divider()
                        switch router.authState {
                        case .loading:
                            Button("Checking Account...") { }
                                .disabled(true)
                        case .signedOut:
                            Button("Sign In") {
                                settingsFocused = false
                                accountSheet = .signIn
                            }
                            .accessibilityHint("Optional. Daily cards are available without an account.")
                        case .signedIn:
                            Button("Log Out", role: .destructive) { logOut() }
                                .disabled(accountRequest.isWorking)
                            Button("Delete Account", role: .destructive) {
                                deletionRequest.clearFeedback()
                                settingsFocused = false
                                accountSheet = .deletion
                            }
                            .disabled(accountRequest.isWorking)
                        }
                    } label: {
                        Image(systemName: "gearshape")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(shareState.isRendering || shareState.export != nil)
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens privacy, support, and optional account tools.")
                    .accessibilityFocused($settingsFocused)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $accountSheet, onDismiss: {
                deletionRequest.clearFeedback()
                settingsFocused = true
            }) { sheet in
                switch sheet {
                case .signIn:
                    NavigationStack { AuthView() }
                case .deletion:
                    DeleteAccountView(request: deletionRequest)
                }
            }
            .sheet(item: $shareState.export, onDismiss: {
                shareState.sheetDismissed()
                shareFocused = true
            }) { export in
                DailyCardShareSheet(export: export) { failed in
                    shareState.completeActivity(failed: failed)
                }
            }
            .alert("Couldn't Share Card", isPresented: $shareState.hasError) {
                Button("Try Again") { Task { await shareState.retry() } }
                Button("Cancel", role: .cancel) {
                    shareState.finish()
                    shareFocused = true
                }
            } message: {
                Text("The card couldn't be prepared or shared. Please try again.")
            }
            .onChange(of: router.authState) { previous, state in
                // Successful sign-in/deletion (or an external session change) closes
                // the obsolete account sheet without replacing the daily card.
                if let sheet = accountSheet, sheet.shouldDismiss(from: previous, to: state) {
                    accountSheet = nil
                } else if case .signedIn = previous, state == .signedOut {
                    settingsFocused = true
                }
            }
            .alert("Couldn't Log Out", isPresented: Binding(
                get: { accountSheet == nil && accountRequest.errorMessage != nil },
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
