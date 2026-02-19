import FirebaseCore
import SwiftUI

@main
struct DailyWhiskersApp: App {
    @StateObject private var router = AppRouter()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
        }
    }
}
