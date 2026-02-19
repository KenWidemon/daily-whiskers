import SwiftUI

struct AuthView: View {
    private enum TestAccount {
        static let email = "test@dailywhiskers.app"
        static let password = "WhiskersTest123!"
    }

    @EnvironmentObject private var router: AppRouter

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var authError: String?
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Daily Whiskers")
                .font(.system(size: 34, weight: .semibold, design: .rounded))

            Text("A calm cat moment, once per day.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                SecureField("Password", text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Button("Sign In") {
                    Task { await handleEmailSignIn() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking || !isEmailFormValid)

                Button("Create Account") {
                    Task { await handleEmailCreateAccount() }
                }
                .buttonStyle(.bordered)
                .disabled(isWorking || !isEmailFormValid)

#if DEBUG
                Button("Use Test Account") {
                    email = TestAccount.email
                    password = TestAccount.password
                    Task { await handleTestAccountSignInOrCreate() }
                }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundStyle(.secondary)
#endif
            }
            .padding(.horizontal, 24)

            if isWorking {
                ProgressView()
            }

            if let authError {
                Text(authError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()
        }
        .padding()
    }

    private var isEmailFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && password.count >= 6
    }

    private func handleEmailSignIn() async {
        isWorking = true
        authError = nil
        defer { isWorking = false }

        do {
            try await router.signInWithEmail(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
        } catch {
            authError = error.localizedDescription
        }
    }

    private func handleEmailCreateAccount() async {
        isWorking = true
        authError = nil
        defer { isWorking = false }

        do {
            try await router.createEmailAccount(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
        } catch {
            authError = error.localizedDescription
        }
    }

    private func handleTestAccountSignInOrCreate() async {
        isWorking = true
        authError = nil
        defer { isWorking = false }

        do {
            try await router.signInOrCreateEmail(
                email: TestAccount.email,
                password: TestAccount.password
            )
        } catch {
            authError = error.localizedDescription
        }
    }
}
