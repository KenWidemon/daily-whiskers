import FirebaseCore
import SwiftUI

@main
struct DailyWhiskersApp: App {
    @StateObject private var router = AppRouter()

    init() {
#if DEBUG && CI_SMOKE_TESTING
        if CISmokeMode.isEnabled { return }
#endif
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG && CI_SMOKE_TESTING
                if CISmokeMode.savedCardsFixtureURL != nil { SavedCardsLoadFixtureView() }
                else { RootView() }
#else
                RootView()
#endif
            }
                .environmentObject(router)
#if DEBUG && CI_SMOKE_TESTING
                .modifier(CISmokeStillnessFixture())
                // Reserve space for the offline marker so it cannot cover collection actions.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if CISmokeMode.isEnabled {
                        Text("Offline CI smoke")
                            .font(.system(size: 10))
                            .dynamicTypeSize(.medium)
                            .accessibilityIdentifier("ci-smoke-offline")
                            .allowsHitTesting(false)
                    }
                }
#endif
        }
    }
}
