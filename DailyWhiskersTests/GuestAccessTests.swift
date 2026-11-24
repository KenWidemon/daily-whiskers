import Testing
@testable import DailyWhiskers

@Suite("Optional account access")
@MainActor
struct GuestAccessTests {
    @Test("Account sheets are unavailable until the session is resolved")
    func loading() {
        #expect(!SettingsSheet.signIn.isAvailable(for: .loading))
        #expect(!SettingsSheet.deletion.isAvailable(for: .loading))
    }

    @Test("Guests can sign in but cannot delete an account")
    func guest() {
        #expect(SettingsSheet.signIn.isAvailable(for: .signedOut))
        #expect(!SettingsSheet.deletion.isAvailable(for: .signedOut))
    }

    @Test("Signing in closes auth and enables account management")
    func signedIn() {
        let state = AppRouter.AuthState.signedIn(uid: "unit-test")
        #expect(!SettingsSheet.signIn.isAvailable(for: state))
        #expect(SettingsSheet.deletion.isAvailable(for: state))
        #expect(SettingsSheet.signIn.shouldDismiss(from: .signedOut, to: state))
    }

    @Test("Session loss closes deletion and restores optional sign-in")
    func sessionEnds() {
        var state = AppRouter.AuthState.signedIn(uid: "unit-test")
        #expect(SettingsSheet.deletion.isAvailable(for: state))
        #expect(SettingsSheet.deletion.shouldDismiss(from: state, to: .signedOut))
        state = .signedOut
        #expect(!SettingsSheet.deletion.isAvailable(for: state))
        #expect(SettingsSheet.signIn.isAvailable(for: state))
    }

    @Test("A changed identity cannot inherit an open deletion form")
    func changedIdentity() {
        let original = AppRouter.AuthState.signedIn(uid: "original")
        #expect(SettingsSheet.deletion.shouldDismiss(from: original, to: .signedIn(uid: "different")))
        #expect(!SettingsSheet.deletion.shouldDismiss(from: original, to: original))
        #expect(!SettingsSheet.signIn.shouldDismiss(from: .signedOut, to: .signedOut))
    }

    @Test("Device settings remain available across account transitions")
    func deviceSettings() {
        let states: [AppRouter.AuthState] = [.loading, .signedOut, .signedIn(uid: "unit-test")]
        for sheet in [SettingsSheet.reminder, .stillness] {
            for previous in states {
                for current in states {
                    #expect(sheet.isAvailable(for: current))
                    #expect(!sheet.shouldDismiss(from: previous, to: current))
                }
            }
        }
    }

}
