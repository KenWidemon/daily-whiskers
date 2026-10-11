import FirebaseAuth
import Foundation
import Testing
@testable import DailyWhiskers

@Suite("Dedicated registration")
@MainActor
struct RegistrationTests {
    @Test("Invalid input never creates an account", arguments: [
        RegistrationForm(),
        RegistrationForm(email: "cat@", password: "Abcdef12", confirmation: "Abcdef12"),
        RegistrationForm(email: "cat@example.com", password: "short", confirmation: "short"),
        RegistrationForm(email: "cat@example.com", password: String(repeating: "x", count: 4097), confirmation: ""),
        RegistrationForm(email: "cat@example.com", password: "Abcdef12", confirmation: ""),
        RegistrationForm(email: "cat@example.com", password: "Abcdef12", confirmation: "ABCDEF12")
    ])
    func invalidInput(_ form: RegistrationForm) async {
        var calls = 0
        var announcements = 0
        let request = AuthRequestState(announce: { _ in announcements += 1 })
        await request.createAccount(form: form) { _, _ in calls += 1 }
        #expect(calls == 0)
        #expect(announcements == 0)
        #expect(request.errorMessage == form.validationError)
        #expect(request.errorMessage != nil)
        #expect(!request.isWorking)
    }

    @Test("Each required character class is validated before submission", arguments: [
        ("abcdefgh1", "Add an uppercase letter (A–Z) to your password."),
        ("ABCDEFGH1", "Add a lowercase letter (a–z) to your password."),
        ("Abcdefghi", "Add a number (0–9) to your password."),
        ("Éabcdefg1", "Add an uppercase letter (A–Z) to your password."),
        ("Abcdefgh١", "Add a number (0–9) to your password.")
    ])
    func missingCharacterClass(_ password: String, _ message: String) async {
        let request = AuthRequestState()
        let form = RegistrationForm(email: "cat@example.com", password: password, confirmation: password)
        await request.createAccount(form: form) { _, _ in Issue.record("Invalid password reached backend") }
        #expect(request.errorMessage == message)
        #expect(!request.isWorking)
    }

    @Test("Seven characters are rejected even with all required character types")
    func belowMinimum() {
        let form = RegistrationForm(email: "cat@example.com", password: "Abcdef1", confirmation: "Abcdef1")
        #expect(form.validationError == "Use at least 8 characters for your password.")
    }

    @Test("Backend policy rejection never recommends the old six-character minimum")
    func backendPolicyRejection() async {
        let request = AuthRequestState()
        let form = RegistrationForm(email: "cat@example.com", password: "Abcdef12", confirmation: "Abcdef12")
        await request.createAccount(form: form) { _, _ in
            throw NSError(domain: AuthErrorDomain, code: AuthErrorCode.weakPassword.rawValue)
        }
        #expect(request.errorMessage == "Password doesn’t meet the account requirements. Check the requirements and try again.")
        #expect(!request.isWorking)
    }

    @Test("Policy length boundaries", arguments: [8, 4096])
    func boundaries(_ length: Int) {
        let password = "Aa1" + String(repeating: "a", count: length - 3)
        #expect(RegistrationForm(email: "cat@example.com", password: password, confirmation: password).validationError == nil)
    }

    @Test("Unicode length follows Firebase and confirmation compares exact input")
    func unicodePasswords() {
        let emoji = "Aa12" + String(repeating: "🐈", count: 2)
        #expect(RegistrationForm(email: "cat@example.com", password: emoji, confirmation: emoji).validationError == nil)
        let composed = "Abcde12é"
        let decomposed = "Abcde12e\u{301}"
        #expect(composed == decomposed) // Swift equality treats these as equivalent.
        #expect(RegistrationForm(email: "cat@example.com", password: composed, confirmation: decomposed).validationError != nil)
    }

    @Test("Registration normalizes only email and releases the lock after success")
    func successfulRegistration() async {
        let request = AuthRequestState()
        request.errorMessage = "Previous error"
        let form = RegistrationForm(email: " \nCat@example.com ", password: " Secret1 ", confirmation: " Secret1 ")
        var calls = 0
        await request.createAccount(form: form) { email, password in
            calls += 1
            #expect(request.operation == .createAccount)
            #expect(request.errorMessage == nil)
            #expect(email == "Cat@example.com")
            #expect(password == " Secret1 ")
        }
        #expect(calls == 1)
        #expect(!request.isWorking)
        #expect(request.errorMessage == nil)
    }

    @Test("Failure and repeated invalid retries are accessible and retryable")
    func retry() async {
        let request = AuthRequestState()
        let valid = RegistrationForm(email: "cat@example.com", password: "Abcdef12", confirmation: "Abcdef12")
        await request.createAccount(form: valid) { _, _ in
            throw NSError(domain: AuthErrorDomain, code: AuthErrorCode.networkError.rawValue)
        }
        #expect(request.errorMessage == "Network error. Check your connection and try again.")
        #expect(!request.isWorking)
        await request.createAccount(form: RegistrationForm()) { _, _ in Issue.record("Invalid request reached backend") }
        let firstID = request.errorPresentationID
        await request.createAccount(form: RegistrationForm()) { _, _ in Issue.record("Invalid request reached backend") }
        #expect(firstID != request.errorPresentationID)
        await request.createAccount(form: valid) { _, _ in }
        #expect(request.errorMessage == nil)
        #expect(!request.isWorking)
    }

    @Test("Pending auth blocks registration before validation or submission")
    func sharedLock() async {
        let request = AuthRequestState()
        await request.perform(.passwordReset) {
            await request.createAccount(form: RegistrationForm()) { _, _ in Issue.record("Duplicate request") }
            #expect(request.errorMessage == nil)
            #expect(request.operation == .passwordReset)
        }
    }

    @Test("Registration cannot be submitted twice while its first request is suspended")
    func duplicateRegistration() async {
        let request = AuthRequestState()
        let form = RegistrationForm(email: "cat@example.com", password: "Abcdef12", confirmation: "Abcdef12")
        var finish: CheckedContinuation<Void, Never>?
        var first: Task<Void, Never>?
        await withCheckedContinuation { started in
            first = Task {
                await request.createAccount(form: form) { _, _ in
                    await withCheckedContinuation { continuation in
                        finish = continuation
                        started.resume()
                    }
                }
            }
        }
        await request.createAccount(form: form) { _, _ in Issue.record("Duplicate registration") }
        await request.perform(.signIn) { Issue.record("Concurrent sign in") }
        #expect(request.operation == .createAccount)
        finish?.resume()
        await first?.value
        #expect(!request.isWorking)
    }

    @Test("Masking preserves input; leaving registration clears both passwords")
    func transientCredentials() {
        var form = RegistrationForm(email: "cat@example.com", password: "Abcdef12", confirmation: "Abcdef12")
        #expect(!form.passwordVisible && !form.confirmationVisible)
        form.passwordVisible = true
        form.confirmationVisible = true
        form.maskPasswords()
        #expect(form.password == "Abcdef12" && form.confirmation == "Abcdef12")
        #expect(!form.passwordVisible && !form.confirmationVisible)
        form.clearPasswords()
        #expect(form.password.isEmpty && form.confirmation.isEmpty)
        #expect(!form.passwordVisible && !form.confirmationVisible)
    }
}
