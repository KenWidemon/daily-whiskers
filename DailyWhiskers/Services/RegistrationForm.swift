import Foundation

/// Transient registration input. Never persisted or shared with Sign In.
struct RegistrationForm: Equatable {
    var email = ""
    var password = ""
    var confirmation = ""
    var passwordVisible = false
    var confirmationVisible = false

    // Ken's selected Apple Account-style baseline for new registrations.
    // Firebase still permits six-character passwords; see the README's policy
    // alignment note. Never apply these new-account rules to existing sign-ins.
    static let minimumPasswordLength = 8
    static let maximumPasswordLength = 4096
    static let passwordRequirements = "Use at least \(minimumPasswordLength) characters, including an uppercase letter, a lowercase letter, and a number."
    static let passwordRules = "required: upper; required: lower; required: digit; minlength: \(minimumPasswordLength); maxlength: \(maximumPasswordLength);"

    @MainActor
    var validationError: String? {
        if !AuthRequestState.isValidEmail(email) { return "Enter a valid email address." }
        // Match Firebase's reference client policy validator (UTF-16 length).
        let length = password.utf16.count
        if length < Self.minimumPasswordLength { return "Use at least \(Self.minimumPasswordLength) characters for your password." }
        if length > Self.maximumPasswordLength { return "Use no more than \(Self.maximumPasswordLength) characters for your password." }
        // Firebase's configurable character classes and Apple's AutoFill rule
        // descriptors use ASCII letters/digits. Other characters remain allowed.
        if !password.utf8.contains(where: { (65...90).contains($0) }) {
            return "Add an uppercase letter (A–Z) to your password."
        }
        if !password.utf8.contains(where: { (97...122).contains($0) }) {
            return "Add a lowercase letter (a–z) to your password."
        }
        if !password.utf8.contains(where: { (48...57).contains($0) }) {
            return "Add a number (0–9) to your password."
        }
        if !password.utf8.elementsEqual(confirmation.utf8) { return "Passwords don’t match. Enter the same password in both fields." }
        return nil
    }

    mutating func maskPasswords() {
        passwordVisible = false
        confirmationVisible = false
    }

    mutating func clearPasswords() {
        password = ""
        confirmation = ""
        maskPasswords()
    }
}

extension AuthRequestState {
    func createAccount(form: RegistrationForm, create: (String, String) async throws -> Void) async {
        guard !isWorking else { return }
        guard form.validationError == nil else {
            clearFeedback()
            errorMessage = form.validationError
            return
        }
        await perform(.createAccount) {
            try await create(Self.normalizedEmail(form.email), form.password)
        }
    }
}
