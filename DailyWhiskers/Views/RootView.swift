import SwiftUI

struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch router.authState {
            case .loading:
                ProgressView("Loading")
            case .signedOut:
                NavigationStack {
                    AuthView()
                        .toolbar(.hidden, for: .navigationBar)
                }
            case .signedIn:
                DailyWhiskersView()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: router.authState)
    }
}
