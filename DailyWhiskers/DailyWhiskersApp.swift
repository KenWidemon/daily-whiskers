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
            RootView()
                .environmentObject(router)
                .overlay(alignment: .bottom) {
#if DEBUG && CI_SMOKE_TESTING
                    if CISmokeMode.isEnabled {
                        Text("Offline CI smoke")
                            .accessibilityIdentifier("ci-smoke-offline")
                    }
#endif
                }
        }
    }
}
