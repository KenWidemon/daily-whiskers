import SwiftUI

#if !targetEnvironment(simulator)
#error("Screenshot capture is simulator-only. Never distribute this target.")
#endif

@main
struct CaptureApp: App {
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
        }
    }
}

// Only the isolated capture project compiles this router. Firebase is never configured.
@MainActor
final class AppRouter: ObservableObject {
    enum AuthState: Equatable {
        case loading
        case signedOut
        case signedIn(uid: String)
    }

    @Published private(set) var authState: AuthState =
        ProcessInfo.processInfo.arguments.contains("--login")
        ? .signedOut : .signedIn(uid: "screenshot-only")

    private enum CaptureError: LocalizedError {
        case disabled
        var errorDescription: String? { "Account actions are disabled in screenshot previews." }
    }

    func signInWithEmail(email: String, password: String) async throws { throw CaptureError.disabled }
    func createEmailAccount(email: String, password: String) async throws { throw CaptureError.disabled }
    func signInOrCreateEmail(email: String, password: String) async throws { throw CaptureError.disabled }
    func sendPasswordReset(email: String) async throws { throw CaptureError.disabled }
    func deleteAccount(password: String) async throws { throw CaptureError.disabled }
    func signOut() throws { throw CaptureError.disabled }
}
