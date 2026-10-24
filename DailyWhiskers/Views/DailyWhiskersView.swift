import SwiftUI
import Combine

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
    @Environment(\.dynamicTypeSize) private var textSize

    @StateObject private var savedCards = SavedCardsModel()
    @State private var bonusCard: RetainedCard?
    @State private var bonusDay = BonusDay(date: Date())
    @State private var openingBonus = false
    @State private var bonusError: String?
    private let dayCheck = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    @State private var capturedInput: DailyCard?
    @State private var displayedArtwork: UIImage?
    @State private var displayedSnapshot: RetainedCard?
    @State private var captureError: String?
    @State private var confirmingClear = false
    @AccessibilityFocusState private var cardOptionsFocused: Bool
    @State private var contentState = DailyContentState()
    @StateObject private var accountRequest = AuthRequestState()
    @StateObject private var deletionRequest = AuthRequestState()
    @State private var accountSheet: AccountSheet?
    @StateObject private var shareState = DailyCardShareState()
    @AccessibilityFocusState private var settingsFocused: Bool

    private var activeSnapshot: RetainedCard? {
        if let bonusCard { return bonusCard }
        guard capturedInput == contentState.currentCard else { return nil }
        return displayedSnapshot
    }

    private var saveState: CardSaveState {
        CardSaveState(isSaved: activeSnapshot.map { savedCards.contains($0.snapshot.id) } == true)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if let bonusCard, let image = UIImage(data: bonusCard.artwork) {
                    DailyRitualCardView(data: DailyCardData(archetype: bonusCard.snapshot.archetype,
                        imageName: "", quote: bonusCard.snapshot.quote, vibe: bonusCard.snapshot.vibe ?? ""),
                        retainedArtwork: image, accessibilityPrefix: "bonus-card")
                        .accessibilityIdentifier("bonus-card")
                } else if let entry = contentState.currentCard {
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
                if newPhase == .active { refreshDay() }
            }
            .onReceive(dayCheck) { _ in refreshDay() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refreshDay() }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshDay() }
            .task(id: contentState.currentCard) { await captureDisplayedCard() }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        if bonusCard != nil {
                            Button("Return to Today", systemImage: "sun.max") { bonusCard = nil }
                        } else {
                            Button("Open Bonus Card", systemImage: "sparkles") { Task { await openBonus() } }
                            Text("One per day, on this device.")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(bonusCard == nil ? "Today" : "Bonus").lineLimit(1)
                            // Leave room for the readable state label on compact phones
                            // at accessibility sizes; the menu keeps its full spoken hint.
                            if !textSize.isAccessibilitySize {
                                Image(systemName: "chevron.down").font(.caption2).accessibilityHidden(true)
                            }
                        }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }
                    .accessibilityLabel(bonusCard == nil ? "Today, Card Menu" : "Bonus Card, Card Menu")
                    .accessibilityHint(bonusCard == nil ? "Open your optional daily bonus." : "Return to today's card.")
                    .accessibilityIdentifier("card-menu")
                    .disabled(openingBonus || accountSheet != nil || shareState.isRendering || shareState.export != nil)
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { SavedCardsView(model: savedCards) } label: {
                        Label("Saved Cards", systemImage: "rectangle.stack")
                    }.accessibilityIdentifier("open-saved-cards")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            guard let snapshot = activeSnapshot else { return }
                            cardOptionsFocused = false
                            Task { await shareState.start(retained: snapshot) }
                        } label: {
                            Label(bonusCard == nil ? "Share Today's Card" : "Share Bonus Card",
                                  systemImage: "square.and.arrow.up")
                        }
                        .accessibilityHint("Shares the artwork and quote. You choose where to send it.")
                        .accessibilityIdentifier("share-daily-card")
                        Button(role: saveState.isSaved ? .destructive : nil) {
                            guard let snapshot = activeSnapshot else { return }
                            Task { await savedCards.toggle(snapshot); cardOptionsFocused = true }
                        } label: {
                            Label { Text(saveState.actionLabel) } icon: { saveState.icon }
                        }
                        .accessibilityValue(saveState.value)
                        .accessibilityHint(saveState.hint)
                        .accessibilityIdentifier("save-daily-card")
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .disabled(activeSnapshot == nil || savedCards.busy || accountSheet != nil || shareState.isRendering || shareState.export != nil)
                    .accessibilityLabel(shareState.isRendering ? "Preparing Card" : (bonusCard == nil ? "Today's Card Options" : "Bonus Card Options"))
                    .accessibilityHint("Opens share, save, and remove actions for this card.")
                    .accessibilityValue(saveState.value)
                    .accessibilityIdentifier("daily-card-options")
                    .accessibilityFocused($cardOptionsFocused)
                    // Anchor the share sheet to a control that survives menu dismissal.
                    .background {
                        DailyCardShareSheet(export: shareState.export) { failed in
                            shareState.completeActivity(failed: failed)
                            shareState.sheetDismissed()
                            cardOptionsFocused = true
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Clear Saved Cards", role: .destructive) { confirmingClear = true }
                            .disabled(!savedCards.canClear)
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
            .alert("Bonus Card Unavailable", isPresented: Binding(get: { bonusError != nil }, set: { if !$0 { bonusError = nil } })) {
                Button("Try Again") { Task { await openBonus() } }
                Button("Return to Today", role: .cancel) { bonusError = nil; bonusCard = nil }
            } message: { Text(bonusError ?? "") }
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
                    cardOptionsFocused = true
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

    private func refreshDay() {
        let now = Date()
        let day = BonusDay(date: now)
        if day.key != bonusDay.key { bonusCard = nil }
        bonusDay = day
        contentState.refresh(at: now)
    }

    private func openBonus() async {
        guard !openingBonus else { return }
        refreshDay()
        openingBonus = true
        bonusError = nil
        let requestedDay = bonusDay
        defer { openingBonus = false }
        do {
            let selected: RetainedCard
            if let retained = try await CardRepository.shared.retainedBonus(on: requestedDay) {
                selected = retained
            } else {
                guard capturedInput == contentState.currentCard, let today = displayedSnapshot else {
                    throw BonusCardError.todayUnavailable
                }
                selected = try await CardRepository.shared.bonus(on: requestedDay, today: today,
                    candidates: DailyContentProvider().bonusCandidates)
            }
            refreshDay()
            guard requestedDay.key == bonusDay.key, !Task.isCancelled else { return }
            bonusCard = selected
            await savedCards.refresh()
        } catch {
            bonusError = (error as? LocalizedError)?.errorDescription ?? "Your bonus couldn't be opened. Please try again; your daily selection is kept."
        }
    }

    private func captureDisplayedCard() async {
        displayedSnapshot = nil
        capturedInput = nil
        displayedArtwork = nil
        guard let card = contentState.currentCard else { return }
        do {
            #if DEBUG && CI_SMOKE_TESTING
            if CISmokeMode.isEnabled && ProcessInfo.processInfo.arguments.contains("--ci-smoke-today-artwork-unavailable") {
                throw CardStorageError.unavailable
            }
            #endif
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

/// Original heart-eyes cat vector, shared as a template image so native menus
/// retain the same artwork as the toolbar and empty-state guidance.
@MainActor
enum HeartEyesCatIcon {
    private static var drawing: Path {
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

    static let unsavedImage = render(isSaved: false)
    static let savedImage = render(isSaved: true)

    private static func render(isSaved: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).image { context in
            let cg = context.cgContext
            cg.saveGState()
            cg.translateBy(x: 4, y: 4)
            cg.addPath(drawing.cgPath)
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillPath()
            cg.restoreGState()
            if isSaved {
                // Keep the original lower-trailing check badge and a clear cutout
                // behind it; template tinting must not fill the check's negative space.
                let badge = CGRect(x: 20, y: 20, width: 12, height: 12)
                cg.setBlendMode(.clear)
                cg.fillEllipse(in: badge)
                cg.setBlendMode(.normal)
                UIImage(systemName: "checkmark.circle.fill",
                        withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))?
                    .withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: badge)
            }
        }.withRenderingMode(.alwaysTemplate)
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
