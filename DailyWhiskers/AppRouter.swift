import FirebaseAuth
import Foundation

@MainActor
final class AppRouter: ObservableObject {
    enum AuthState: Equatable {
        case loading
        case signedOut
        case signedIn(uid: String)
    }

    @Published private(set) var authState: AuthState = .loading

    private var authHandle: AuthStateDidChangeListenerHandle?

    init() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            self.authState = user.map { .signedIn(uid: $0.uid) } ?? .signedOut
        }
    }

    deinit {
        if let authHandle {
            Auth.auth().removeStateDidChangeListener(authHandle)
        }
    }

    func signInWithEmail(email: String, password: String) async throws {
        _ = try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func createEmailAccount(email: String, password: String) async throws {
        _ = try await Auth.auth().createUser(withEmail: email, password: password)
    }

    func signInOrCreateEmail(email: String, password: String) async throws {
        do {
            try await signInWithEmail(email: email, password: password)
        } catch {
            guard isUserNotFound(error) else {
                throw error
            }
            try await createEmailAccount(email: email, password: password)
        }
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    private func isUserNotFound(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard let code = AuthErrorCode(rawValue: nsError.code) else {
            return false
        }
        return code == .userNotFound
    }
}
