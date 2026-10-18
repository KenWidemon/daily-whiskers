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

    @StateObject private var savedCards = SavedCardsModel()
    @State private var capturedInput: DailyCard?
    @State private var displayedArtwork: UIImage?
    @State private var displayedSnapshot: RetainedCard?
    @State private var captureError: String?
    @State private var confirmingClear = false
    @AccessibilityFocusState private var saveFocused: Bool
    @State private var contentState = DailyContentState()
    @StateObject private var accountRequest = AuthRequestState()
    @StateObject private var deletionRequest = AuthRequestState()
    @State private var accountSheet: AccountSheet?
    @StateObject private var shareState = DailyCardShareState()
    @AccessibilityFocusState private var shareFocused: Bool
    @AccessibilityFocusState private var settingsFocused: Bool

    private var activeSnapshot: RetainedCard? {
        guard capturedInput == contentState.currentCard else { return nil }
        return displayedSnapshot
    }

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
                        ), retainedArtwork: displayedArtwork
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
            .task(id: contentState.currentCard) { await captureDisplayedCard() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { SavedCardsView(model: savedCards) } label: {
                        Label("Saved Cards", systemImage: "rectangle.stack")
                    }.accessibilityIdentifier("open-saved-cards")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard let displayedSnapshot = activeSnapshot else { Task { await captureDisplayedCard() }; return }
                        Task { await savedCards.toggle(displayedSnapshot); saveFocused = true }
                    } label: {
                        HeartEyesCatIcon()
                            .frame(width: 32, height: 32)
                            .overlay(alignment: .bottomTrailing) {
                                if activeSnapshot.map({ savedCards.contains($0.snapshot.id) }) == true {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.black, .white)
                                }
                            }
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(activeSnapshot == nil || savedCards.busy || accountSheet != nil || shareState.isRendering || shareState.export != nil)
                    .accessibilityValue(activeSnapshot.map { savedCards.contains($0.snapshot.id) } == true ? "Saved" : "Not saved")
                    .accessibilityLabel("Save Card")
                    .accessibilityHint(activeSnapshot.map { savedCards.contains($0.snapshot.id) } == true ? "Removes this card from Saved Cards." : "Saves this card on this device.")
                    .accessibilityIdentifier("save-daily-card")
                    .accessibilityFocused($saveFocused)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard let snapshot = activeSnapshot else { return }
                        shareFocused = false
                        Task { await shareState.start(retained: snapshot) }
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
                    .disabled(activeSnapshot == nil || accountSheet != nil || shareState.isRendering || shareState.export != nil)
                    .accessibilityLabel(shareState.isRendering ? "Preparing Card" : "Share Today's Card")
                    .accessibilityHint("Shares the artwork and quote. You choose where to send it.")
                    .accessibilityIdentifier("share-daily-card")
                    .accessibilityFocused($shareFocused)
                    .background {
                        DailyCardShareSheet(export: shareState.export) { failed in
                            shareState.completeActivity(failed: failed)
                            shareState.sheetDismissed()
                            shareFocused = true
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Clear Saved Cards", role: .destructive) { confirmingClear = true }
                            .disabled(savedCards.busy)
                        Divider()
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
                    // A closing menu must not restore focus behind its account sheet.
                    .accessibilityHidden(accountSheet != nil)
                }
            }
            .modifier(SavedCardsError(model: savedCards))
            .alert("Clear Saved Cards?", isPresented: $confirmingClear) {
                Button("Clear Saved Cards", role: .destructive) { Task { await savedCards.clear(); settingsFocused = true } }
                Button("Cancel", role: .cancel) { settingsFocused = true }
            } message: {
                Text("This removes all saved cards from this app. Your current card and daily or bonus selections are kept. Existing device backups are not changed.")
            }
            .alert("Couldn't Prepare Card", isPresented: Binding(get: { captureError != nil }, set: { if !$0 { captureError = nil } })) {
                Button("Try Again") { Task { await captureDisplayedCard() } }
                Button("Cancel", role: .cancel) { captureError = nil }
            } message: { Text(captureError ?? "") }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $accountSheet, onDismiss: {
                // A previous dismissal must not focus Settings over a replacement sheet.
                guard accountSheet == nil else { return }
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

    private func captureDisplayedCard() async {
        displayedSnapshot = nil
        capturedInput = nil
        displayedArtwork = nil
        guard let card = contentState.currentCard else { return }
        do {
            let captured = try await CardRepository.shared.capture(card)
            guard !Task.isCancelled, contentState.currentCard == card else { return }
            capturedInput = card
            displayedArtwork = UIImage(data: captured.artwork)
            displayedSnapshot = captured
            await savedCards.refresh()
        } catch {
            captureError = "The original artwork couldn't be loaded. Please try again."
        }
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

/// A template-style vector using the dark toolbar's primary foreground color.
private struct HeartEyesCatIcon: View {
    private var drawing: Path {
        let outline = Path { path in
            path.move(to: CGPoint(x: 3.5, y: 9))
            path.addLine(to: CGPoint(x: 3, y: 2))
            path.addLine(to: CGPoint(x: 9, y: 5.7))
            path.addQuadCurve(to: CGPoint(x: 15, y: 5.7), control: CGPoint(x: 12, y: 4.3))
            path.addLine(to: CGPoint(x: 21, y: 2))
            path.addLine(to: CGPoint(x: 20.5, y: 9))
            path.addCurve(to: CGPoint(x: 12, y: 22), control1: CGPoint(x: 24, y: 16), control2: CGPoint(x: 19, y: 22))
            path.addCurve(to: CGPoint(x: 3.5, y: 9), control1: CGPoint(x: 5, y: 22), control2: CGPoint(x: 0, y: 16))
            path.closeSubpath()
            path.move(to: CGPoint(x: 8.5, y: 16.5))
            path.addQuadCurve(to: CGPoint(x: 15.5, y: 16.5), control: CGPoint(x: 12, y: 20.5))
            for y: CGFloat in [13, 16] {
                path.move(to: CGPoint(x: 0.8, y: y))
                path.addLine(to: CGPoint(x: 4.5, y: y + 0.6))
                path.move(to: CGPoint(x: 23.2, y: y))
                path.addLine(to: CGPoint(x: 19.5, y: y + 0.6))
            }
        }.strokedPath(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        let eyes = Path { path in
            for x: CGFloat in [7.8, 16.2] {
                path.move(to: CGPoint(x: x, y: 10))
                path.addCurve(to: CGPoint(x: x - 2.8, y: 10.5),
                              control1: CGPoint(x: x - 1.8, y: 7.7), control2: CGPoint(x: x - 3.6, y: 9))
                path.addCurve(to: CGPoint(x: x, y: 14),
                              control1: CGPoint(x: x - 2.5, y: 11.7), control2: CGPoint(x: x - 0.7, y: 13.3))
                path.addCurve(to: CGPoint(x: x + 2.8, y: 10.5),
                              control1: CGPoint(x: x + 0.7, y: 13.3), control2: CGPoint(x: x + 2.5, y: 11.7))
                path.addCurve(to: CGPoint(x: x, y: 10),
                              control1: CGPoint(x: x + 3.6, y: 9), control2: CGPoint(x: x + 1.8, y: 7.7))
                path.closeSubpath()
            }
        }
        // One foreground layer keeps the heart eyes at the same color as the outline.
        var result = outline
        result.addPath(eyes)
        return result
    }

    var body: some View {
        drawing.fill(Color.primary)
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
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
