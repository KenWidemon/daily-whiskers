import FirebaseAuth
import Foundation
import Testing
@testable import DailyWhiskers

@Suite("Dedicated registration")
@MainActor
struct RegistrationTests {
    @Test("Password entry requires nonblank email, not a valid address", arguments: [
        ("", false), (" \t\n", false), ("\u{00a0}", false), ("a", true), ("cat@", true), (" cat@example.invalid ", true)
    ])
    func emailFirstEntry(_ email: String, _ available: Bool) {
        #expect(RegistrationForm(email: email).canEditPassword == available)
    }

    @Test("Clearing email remasks without clearing the exact password; restoring email stays masked",
          arguments: ["", " \t\n"])
    func clearingEmailRetainsPassword(_ blank: String) {
        let original = " Aé🐈1z "
        var form = RegistrationForm(email: "cat@", password: original, passwordVisible: true)
        form.email = blank
        #expect(!form.canEditPassword)
        #expect(!form.passwordVisible)
        #expect(form.password.utf8.elementsEqual(original.utf8))
        form.email = "x"
        #expect(form.canEditPassword)
        #expect(!form.passwordVisible)
        #expect(form.password.utf8.elementsEqual(original.utf8))
    }

    @Test("One password is sufficient and submitted without alteration")
    func singlePasswordRegistration() async {
        let request = AuthRequestState()
        let form = RegistrationForm(email: "cat@example.invalid", password: " Synthetic1 ")
        var calls = 0
        await request.createAccount(form: form) { email, password in
            calls += 1
            #expect(email == "cat@example.invalid")
            #expect(password.utf8.elementsEqual(form.password.utf8))
        }
        #expect(calls == 1)
        #expect(request.errorMessage == nil)
    }

    @Test("Invalid input never creates an account", arguments: [
        RegistrationForm(),
        RegistrationForm(email: "cat@", password: "Abcdef12"),
        RegistrationForm(email: "cat@example.com", password: "short"),
        RegistrationForm(email: "cat@example.com", password: String(repeating: "x", count: 4097)),
        RegistrationForm(email: "cat@example.com", password: "")
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
        let form = RegistrationForm(email: "cat@example.com", password: password)
        await request.createAccount(form: form) { _, _ in Issue.record("Invalid password reached backend") }
        #expect(request.errorMessage == message)
        #expect(!request.isWorking)
    }

    @Test("Seven characters are rejected even with all required character types")
    func belowMinimum() {
        let form = RegistrationForm(email: "cat@example.com", password: "Abcdef1")
        #expect(form.validationError == "Use at least 8 characters for your password.")
    }

    @Test("Backend policy rejection never recommends the old six-character minimum")
    func backendPolicyRejection() async {
        let request = AuthRequestState()
        let form = RegistrationForm(email: "cat@example.com", password: "Abcdef12")
        await request.createAccount(form: form) { _, _ in
            throw NSError(domain: AuthErrorDomain, code: AuthErrorCode.weakPassword.rawValue)
        }
        #expect(request.errorMessage == "Password doesn’t meet the account requirements. Check the requirements and try again.")
        #expect(!request.isWorking)
    }

    @Test("Policy length boundaries", arguments: [8, 4096])
    func boundaries(_ length: Int) {
        let password = "Aa1" + String(repeating: "a", count: length - 3)
        #expect(RegistrationForm(email: "cat@example.com", password: password).validationError == nil)
    }

    @Test("Unicode length and exact password bytes are preserved")
    func unicodePasswords() async {
        let emoji = "Aa12" + String(repeating: "🐈", count: 2)
        #expect(RegistrationForm(email: "cat@example.com", password: emoji).validationError == nil)
        let composed = "Abcde12é"
        let decomposed = "Abcde12e\u{301}"
        #expect(composed == decomposed) // Swift equality hides byte differences.
        #expect(!composed.utf8.elementsEqual(decomposed.utf8))
        var calls = 0
        for password in [composed, decomposed] {
            let form = RegistrationForm(email: "cat@example.com", password: password)
            #expect(form.validationError == nil)
            await AuthRequestState().createAccount(form: form) { _, submitted in
                calls += 1
                #expect(submitted.utf8.elementsEqual(password.utf8))
            }
        }
        #expect(calls == 2)
    }

    @Test("Registration normalizes only email and releases the lock after success")
    func successfulRegistration() async {
        let request = AuthRequestState()
        request.errorMessage = "Previous error"
        let form = RegistrationForm(email: " \nCat@example.com ", password: " Secret1 ")
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
        let valid = RegistrationForm(email: "cat@example.com", password: "Abcdef12")
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
        let form = RegistrationForm(email: "cat@example.com", password: "Abcdef12")
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

    @Test("Masking preserves input; leaving registration clears the password")
    func transientCredentials() {
        var form = RegistrationForm(email: "cat@example.com", password: "Abcdef12")
        #expect(!form.passwordVisible)
        form.passwordVisible = true
        form.maskPasswords()
        #expect(form.password == "Abcdef12")
        #expect(!form.passwordVisible)
        form.clearPasswords()
        #expect(form.password.isEmpty)
        #expect(!form.passwordVisible)
    }
}
