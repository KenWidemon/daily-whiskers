import FirebaseAuth
import Foundation
import Testing
@testable import DailyWhiskers

@Suite("Auth recovery")
@MainActor
struct AuthRecoveryTests {
    private func error(_ code: AuthErrorCode) -> NSError {
        NSError(domain: AuthErrorDomain, code: code.rawValue)
    }

    @Test("Invalid reset emails never call the backend", arguments: ["", "   ", "cat", "cat@", "cat@example", "cat name@example.com"])
    func invalidEmail(_ email: String) async {
        let state = AuthRequestState()
        var calls = 0
        await state.resetPassword(email: email) { _ in calls += 1 }
        #expect(calls == 0)
        #expect(state.errorMessage == "Enter a valid email address.")
        #expect(state.confirmation == nil)
        #expect(!state.isWorking)
    }

    @Test("Repeated identical validation failures each request a new error presentation")
    func repeatedValidationPresentation() async {
        let state = AuthRequestState()
        var calls = 0
        let initialID = state.errorPresentationID
        await state.resetPassword(email: "") { _ in calls += 1 }
        let firstID = state.errorPresentationID
        await state.resetPassword(email: "") { _ in calls += 1 }
        #expect(firstID != initialID)
        #expect(state.errorPresentationID != firstID)
        #expect(state.errorMessage == "Enter a valid email address.")
        #expect(calls == 0)

        let lastID = state.errorPresentationID
        state.clearFeedback()
        #expect(state.errorMessage == nil)
        #expect(state.errorPresentationID == lastID)
    }

    @Test("Repeated backend failures each request a new error presentation")
    func repeatedBackendErrorPresentation() async {
        let state = AuthRequestState()
        await state.perform(.signIn) { throw error(.networkError) }
        let firstID = state.errorPresentationID
        await state.perform(.signIn) { throw error(.networkError) }
        #expect(state.errorPresentationID != firstID)
        #expect(state.errorMessage == "Network error. Check your connection and try again.")
    }

    @Test("Accepted requests announce before even immediately completed work", arguments: [
        AuthRequestState.Operation.signIn, .createAccount, .testAccount, .passwordReset
    ])
    func announcementBeforeAction(_ operation: AuthRequestState.Operation) async {
        var events: [String] = []
        let state = AuthRequestState(announce: { events.append($0.announcement) })
        await state.perform(operation) {
            #expect(state.isWorking)
            events.append("action")
        }
        #expect(events == [operation.announcement, "action"])
        #expect(!state.isWorking)
    }

    @Test("Blocked duplicate requests do not announce")
    func blockedRequestsStaySilent() async {
        var announcements: [String] = []
        let state = AuthRequestState(announce: { announcements.append($0.announcement) })
        var duplicateCalls = 0
        await state.perform(.signIn) {
            for operation in [AuthRequestState.Operation.signIn, .createAccount,
                              .testAccount, .passwordReset, .logout, .deleteAccount] {
                await state.perform(operation) { duplicateCalls += 1 }
            }
            await state.resetPassword(email: "cat@example.com") { _ in duplicateCalls += 1 }
        }
        #expect(duplicateCalls == 0)
        #expect(announcements == ["Signing in."])
    }

    @Test("Invalid reset is silent and separate accepted retries each announce")
    func validationAndRetryAnnouncements() async {
        var announcements: [String] = []
        let state = AuthRequestState(announce: { announcements.append($0.announcement) })
        var calls = 0
        await state.resetPassword(email: "") { _ in calls += 1 }
        #expect(calls == 0)
        #expect(announcements.isEmpty)
        for _ in 0..<2 {
            await state.perform(.signIn) { throw error(.networkError) }
        }
        #expect(announcements == ["Signing in.", "Signing in."])
    }

    @Test("Reset trims email and does not need a password")
    func validReset() async {
        let state = AuthRequestState()
        var sentEmail: String?
        await state.resetPassword(email: " \nCat+test@example.com \t") { email in
            #expect(state.operation == .passwordReset)
            sentEmail = email
        }
        #expect(sentEmail == "Cat+test@example.com")
        #expect(state.confirmation == AuthErrorMapper.resetConfirmation)
        #expect(state.errorMessage == nil)
        #expect(!state.isWorking)
    }

    @Test("Missing account and successful reset have identical feedback")
    func neutralConfirmation() async {
        let success = AuthRequestState()
        let missing = AuthRequestState()
        await success.resetPassword(email: "cat@example.com") { _ in }
        await missing.resetPassword(email: "cat@example.com") { _ in throw error(.userNotFound) }
        #expect(missing.confirmation == success.confirmation)
        #expect(missing.errorMessage == nil)
        #expect(!missing.isWorking)
    }

    @Test("Network failure releases the lock and permits retry")
    func failureThenRetry() async {
        let state = AuthRequestState()
        await state.resetPassword(email: "cat@example.com") { _ in throw error(.networkError) }
        #expect(state.errorMessage == "Network error. Check your connection and try again.")
        #expect(state.confirmation == nil)
        #expect(!state.isWorking)
        await state.resetPassword(email: "cat@example.com") { _ in
            #expect(state.errorMessage == nil)
        }
        #expect(state.errorMessage == nil)
        #expect(state.confirmation == AuthErrorMapper.resetConfirmation)
    }

    @Test("An in-flight operation blocks every other auth action", arguments: [
        AuthRequestState.Operation.signIn, .createAccount, .testAccount, .passwordReset, .logout, .deleteAccount
    ])
    func concurrentRequests(_ operation: AuthRequestState.Operation) async {
        let state = AuthRequestState()
        var finish: CheckedContinuation<Void, Never>?
        var first: Task<Void, Never>?
        await withCheckedContinuation { started in
            first = Task {
                await state.perform(operation) {
                    await withCheckedContinuation { continuation in
                        finish = continuation
                        started.resume()
                    }
                }
            }
        }
        var duplicateCalls = 0
        for next in [AuthRequestState.Operation.signIn, .createAccount, .testAccount, .passwordReset, .logout, .deleteAccount] {
            await state.perform(next) { duplicateCalls += 1 }
        }
        await state.resetPassword(email: "cat@example.com") { _ in duplicateCalls += 1 }
        #expect(duplicateCalls == 0)
        #expect(state.operation == operation)
        finish?.resume()
        await first?.value
        #expect(!state.isWorking)
    }

    @Test("Cancellation releases the lock without failure feedback")
    func cancellation() async {
        let state = AuthRequestState()
        await state.perform(.passwordReset) { throw CancellationError() }
        #expect(!state.isWorking)
        #expect(state.errorMessage == nil)
        #expect(state.confirmation == nil)
    }

    @Test("Logout failure is visible and retry clears it")
    func logoutRetry() async {
        let state = AuthRequestState()
        await state.perform(.logout) { throw error(.keychainError) }
        #expect(state.errorMessage == "Couldn't log out. Please try again.")
        #expect(!state.isWorking)
        var didLogOut = false
        await state.perform(.logout) { didLogOut = true }
        #expect(didLogOut)
        #expect(state.errorMessage == nil)
        #expect(state.confirmation == nil)
    }

    @Test("Reset errors are actionable", arguments: [
        (AuthErrorCode.invalidEmail, "Enter a valid email address."),
        (.networkError, "Network error. Check your connection and try again."),
        (.tooManyRequests, "Too many attempts. Please wait a moment and try again."),
        (.internalError, "Couldn't send a reset link. Please try again.")
    ])
    func resetErrors(_ code: AuthErrorCode, _ expected: String) {
        #expect(AuthErrorMapper.message(for: error(code), context: .passwordReset) == expected)
    }

    @Test("Non-Firebase codes do not masquerade as auth errors")
    func foreignError() async {
        let foreign = NSError(domain: "TestError", code: AuthErrorCode.userNotFound.rawValue)
        let state = AuthRequestState()
        await state.resetPassword(email: "cat@example.com") { _ in throw foreign }
        #expect(state.errorMessage == "Couldn't send a reset link. Please try again.")
        #expect(state.confirmation == nil)
    }

    @Test("Sign-in still maps invalid credentials")
    func signInFailure() async {
        let state = AuthRequestState()
        await state.perform(.signIn) { throw error(.invalidCredential) }
        #expect(state.errorMessage == "Invalid email or password.")
        #expect(!state.isWorking)
    }

    @Test("Secure storage failures are distinct from invalid credentials")
    func keychainFailure() {
        #expect(AuthErrorMapper.message(for: error(.keychainError)) ==
            "Couldn't access secure account storage. Restart the app and try again.")
    }

    @Test("Every operation has account-neutral accessibility feedback", arguments: [
        (AuthRequestState.Operation.signIn, "Signing in."),
        (.createAccount, "Creating account."),
        (.testAccount, "Signing in."),
        (.passwordReset, "Sending reset link."),
        (.logout, "Logging out."),
        (.deleteAccount, "Deleting account.")
    ])
    func operationAnnouncement(_ operation: AuthRequestState.Operation, _ expected: String) {
        #expect(operation.announcement == expected)
    }

    @Test("Dismissing feedback clears both alert and inline error state")
    func dismissFeedback() async {
        let state = AuthRequestState()
        await state.perform(.logout) { throw error(.keychainError) }
        state.clearFeedback()
        #expect(state.errorMessage == nil)
        #expect(state.confirmation == nil)
        #expect(!state.isWorking)

        await state.resetPassword(email: "cat@example.com") { _ in }
        #expect(state.confirmation != nil)
        state.clearFeedback()
        #expect(state.errorMessage == nil)
        #expect(state.confirmation == nil)
    }

    @Test("A successful sign-in clears stale feedback and releases the lock")
    func successfulSignIn() async {
        let state = AuthRequestState()
        state.errorMessage = "Previous failure"
        state.confirmation = "Previous confirmation"
        var calls = 0
        await state.perform(.signIn) {
            calls += 1
            #expect(state.operation == .signIn)
            #expect(state.errorMessage == nil)
            #expect(state.confirmation == nil)
        }
        #expect(calls == 1)
        #expect(!state.isWorking)
        #expect(state.errorMessage == nil)
        #expect(state.confirmation == nil)
    }
}
