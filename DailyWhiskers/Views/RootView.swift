import SwiftUI

struct RootView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        Group {
            switch router.authState {
            case .loading:
                ProgressView("Loading")
            case .signedOut:
                AuthView()
            case .signedIn:
                DailyWhiskersView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: router.authState)
    }
}
