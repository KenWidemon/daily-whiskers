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
    @State private var cardOptionsFocused: Bool = false
    @State private var contentState = DailyContentState()
    @StateObject private var accountRequest = AuthRequestState()
    @StateObject private var deletionRequest = AuthRequestState()
    @State private var accountSheet: AccountSheet?
    @StateObject private var shareState = DailyCardShareState()
    @State private var settingsFocused: Bool = false

    private var activeSnapshot: RetainedCard? {
        if let bonusCard { return bonusCard }
        guard capturedInput == contentState.currentCard else { return nil }
        return displayedSnapshot
    }

    private var saveState: CardSaveState {
        CardSaveState(isSaved: activeSnapshot.map { savedCards.contains($0.snapshot.id) } == true)
    }

    private var nativeToolbar: CardNavigationToolbar {
        let share = CardNavigationToolbar.action(bonusCard == nil ? "Share Today's Card" : "Share Bonus Card",
            identifier: "share-daily-card", image: UIImage(systemName: "square.and.arrow.up"),
            hint: "Shares the artwork and quote. You choose where to send it.") {
                guard let snapshot = activeSnapshot else { return }
                cardOptionsFocused = false
                Task { await shareState.start(retained: snapshot) }
            }
        let save = CardNavigationToolbar.action(saveState.actionLabel, identifier: "save-daily-card",
            image: saveState.isSaved ? HeartEyesCatIcon.savedImage : HeartEyesCatIcon.unsavedImage,
            hint: saveState.hint, value: saveState.value, destructive: saveState.isSaved) {
                guard let snapshot = activeSnapshot else { return }
                #if DEBUG && CI_SMOKE_TESTING && SAVED_TIMING_DIAGNOSTIC
                SavedTimingDiagnostic.mark("action.save.dispatched")
                #endif
                Task {
                    #if DEBUG && CI_SMOKE_TESTING && SAVED_TIMING_DIAGNOSTIC
                    SavedTimingDiagnostic.mark("action.save.taskStarted")
                    #endif
                    await savedCards.toggle(snapshot); cardOptionsFocused = true
                    #if DEBUG && CI_SMOKE_TESTING && SAVED_TIMING_DIAGNOSTIC
                    SavedTimingDiagnostic.mark("action.save.taskCompleted")
                    #endif
                }
            }
        return CardNavigationToolbar(options: .init(identifier: "daily-card-options",
            label: shareState.isRendering ? "Preparing Card" : (bonusCard == nil ? "Today's Card Options" : "Bonus Card Options"),
            hint: "Opens share, save, and remove actions for this card.", value: saveState.value,
            image: "ellipsis", enabled: activeSnapshot != nil && !savedCards.busy && accountSheet == nil && !shareState.isRendering && shareState.export == nil,
            menu: UIMenu(children: [share, save])),
            settings: .init(identifier: "Settings", label: "Settings",
                hint: "Opens privacy, support, and optional account tools.", image: "gearshape",
                enabled: !shareState.isRendering && shareState.export == nil,
                hiddenFromAccessibility: accountSheet != nil, menu: nativeSettingsMenu),
            export: shareState.export, onShareComplete: { failed in
                shareState.completeActivity(failed: failed)
                shareState.sheetDismissed()
                cardOptionsFocused = true
            }, optionsFocused: $cardOptionsFocused, settingsFocused: $settingsFocused)
    }

    private var nativeSettingsMenu: UIMenu {
        let clear = CardNavigationToolbar.action("Clear Saved Cards", disabled: !savedCards.canClear,
            destructive: true) { confirmingClear = true }
        let links = [CardNavigationToolbar.action("Privacy Policy") { UIApplication.shared.open(AppLinks.privacyPolicy) },
                     CardNavigationToolbar.action("Support") { UIApplication.shared.open(AppLinks.support) }]
        let account: [UIMenuElement]
        switch router.authState {
        case .loading:
            account = [CardNavigationToolbar.action("Checking Account...", disabled: true) {}]
        case .signedOut:
            account = [CardNavigationToolbar.action("Sign In", hint: "Optional. Daily cards are available without an account.") {
                settingsFocused = false; accountSheet = .signIn
            }]
        case .signedIn:
            account = [CardNavigationToolbar.action("Log Out", disabled: accountRequest.isWorking, destructive: true) { logOut() },
                       CardNavigationToolbar.action("Delete Account", disabled: accountRequest.isWorking, destructive: true) {
                           deletionRequest.clearFeedback(); settingsFocused = false; accountSheet = .deletion
                       }]
        }
        return UIMenu(children: [UIMenu(options: .displayInline, children: [clear]),
                                 UIMenu(options: .displayInline, children: links),
                                 UIMenu(options: .displayInline, children: account)])
    }

    var body: some View {
        NavigationStack {
            cardContent
            .onAppear {
                contentState.refresh(at: Date(), force: true)
            }
            .onChange(of: scenePhase) { (_: ScenePhase, newPhase: ScenePhase) in
                if newPhase == .active { refreshDay() }
            }
            .onReceive(dayCheck) { _ in refreshDay() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refreshDay() }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshDay() }
            .task(id: contentState.currentCard) { await captureDisplayedCard() }
            .toolbar { cardToolbar }
            .background { nativeToolbar.frame(width: 0, height: 0) }
            .modifier(SavedCardsError(model: savedCards))
            .alert("Clear Saved Cards?", isPresented: $confirmingClear) {
                Button("Clear Saved Cards", role: .destructive) { Task { await savedCards.clear(); settingsFocused = true } }
                Button("Cancel", role: .cancel) { settingsFocused = true }
            } message: {
                Text("This removes all saved cards from this app. Your current card and daily or bonus selections are kept. Existing device backups are not changed.")
            }
            .alert("Couldn't Prepare Card", isPresented: captureErrorPresented) {
                Button("Try Again") { Task { await captureDisplayedCard() } }
                Button("Cancel", role: .cancel) { captureError = nil }
            } message: { Text(captureError ?? "") }
            .alert("Bonus Card Unavailable", isPresented: bonusErrorPresented) {
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
                handleAuthStateChange(from: previous, to: state)
            }
            .alert("Couldn't Log Out", isPresented: logoutErrorPresented) {
                Button("Try Again") { logOut() }
                Button("Cancel", role: .cancel) { dismissLogoutError() }
            } message: {
                Text(accountRequest.errorMessage ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var captureErrorPresented: Binding<Bool> {
        Binding<Bool>(get: { captureError != nil }, set: setCaptureErrorPresented)
    }

    private func setCaptureErrorPresented(_ isPresented: Bool) {
        if !isPresented { captureError = nil }
    }

    private var bonusErrorPresented: Binding<Bool> {
        Binding<Bool>(get: { bonusError != nil }, set: setBonusErrorPresented)
    }

    private func setBonusErrorPresented(_ isPresented: Bool) {
        if !isPresented { bonusError = nil }
    }

    private var logoutErrorPresented: Binding<Bool> {
        Binding<Bool>(get: { accountSheet == nil && accountRequest.errorMessage != nil },
                      set: setLogoutErrorPresented)
    }

    private func setLogoutErrorPresented(_ isPresented: Bool) {
        if !isPresented { dismissLogoutError() }
    }

    private var cardContent: some View {
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
    }

    @ToolbarContentBuilder
    private var cardToolbar: some ToolbarContent {
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
    }

    private func handleAuthStateChange(from previous: AppRouter.AuthState, to state: AppRouter.AuthState) {
        // Successful sign-in/deletion (or an external session change) closes
        // the obsolete account sheet without replacing the daily card.
        if let sheet = accountSheet, sheet.shouldDismiss(from: previous, to: state) {
            accountSheet = nil
        } else if case .signedIn = previous, state == .signedOut {
            settingsFocused = true
        }
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
