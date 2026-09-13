import Testing
@testable import DailyWhiskers

@Suite("Optional account access")
@MainActor
struct GuestAccessTests {
    @Test("Account sheets are unavailable until the session is resolved")
    func loading() {
        #expect(!AccountSheet.signIn.isAvailable(for: .loading))
        #expect(!AccountSheet.deletion.isAvailable(for: .loading))
    }

    @Test("Guests can sign in but cannot delete an account")
    func guest() {
        #expect(AccountSheet.signIn.isAvailable(for: .signedOut))
        #expect(!AccountSheet.deletion.isAvailable(for: .signedOut))
    }

    @Test("Signing in closes auth and enables account management")
    func signedIn() {
        let state = AppRouter.AuthState.signedIn(uid: "unit-test")
        #expect(!AccountSheet.signIn.isAvailable(for: state))
        #expect(AccountSheet.deletion.isAvailable(for: state))
        #expect(AccountSheet.signIn.shouldDismiss(from: .signedOut, to: state))
    }

    @Test("Session loss closes deletion and restores optional sign-in")
    func sessionEnds() {
        var state = AppRouter.AuthState.signedIn(uid: "unit-test")
        #expect(AccountSheet.deletion.isAvailable(for: state))
        #expect(AccountSheet.deletion.shouldDismiss(from: state, to: .signedOut))
        state = .signedOut
        #expect(!AccountSheet.deletion.isAvailable(for: state))
        #expect(AccountSheet.signIn.isAvailable(for: state))
    }

    @Test("A changed identity cannot inherit an open deletion form")
    func changedIdentity() {
        let original = AppRouter.AuthState.signedIn(uid: "original")
        #expect(AccountSheet.deletion.shouldDismiss(from: original, to: .signedIn(uid: "different")))
        #expect(!AccountSheet.deletion.shouldDismiss(from: original, to: original))
        #expect(!AccountSheet.signIn.shouldDismiss(from: .signedOut, to: .signedOut))
    }
}
