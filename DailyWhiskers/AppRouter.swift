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
#if DEBUG && CI_SMOKE_TESTING
        if CISmokeMode.isEnabled {
            authState = .signedOut
            return
        }
#endif
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
#if DEBUG && CI_SMOKE_TESTING
        try CISmokeMode.rejectAuthOperation()
#endif
        _ = try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func createEmailAccount(email: String, password: String) async throws {
#if DEBUG && CI_SMOKE_TESTING
        try CISmokeMode.rejectAuthOperation()
#endif
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
#if DEBUG && CI_SMOKE_TESTING
        try CISmokeMode.rejectAuthOperation()
#endif
        try Auth.auth().signOut()
    }

    func sendPasswordReset(email: String) async throws {
#if DEBUG && CI_SMOKE_TESTING
        try CISmokeMode.rejectAuthOperation()
#endif
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    func deleteAccount(password: String) async throws {
#if DEBUG && CI_SMOKE_TESTING
        try CISmokeMode.rejectAuthOperation()
#endif
        let auth = Auth.auth()
        guard let user = auth.currentUser, let email = user.email else {
            throw AccountDeletionError.sessionChanged
        }
        try await AccountDeletion.perform(password: password) { password in
            let credential = EmailAuthProvider.credential(withEmail: email, password: password)
            _ = try await user.reauthenticate(with: credential)
        } delete: {
            guard auth.currentUser?.uid == user.uid else {
                throw AccountDeletionError.sessionChanged
            }
            // Firebase deletes the account and clears its local auth session.
            try await user.delete()
        }
        authState = auth.currentUser.map { .signedIn(uid: $0.uid) } ?? .signedOut
    }

    private func isUserNotFound(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard let code = AuthErrorCode(rawValue: nsError.code) else {
            return false
        }
        return code == .userNotFound
    }
}
