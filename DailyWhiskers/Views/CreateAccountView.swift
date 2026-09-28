import SwiftUI

struct CreateAccountView: View {
    private enum Field: Hashable { case email, password, confirmation }
    private enum AccessibilityTarget: Hashable { case heading, error }
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var request: AuthRequestState
    let scroll: ScrollViewProxy
    let onBack: () -> Void
    @State private var form: RegistrationForm
    @State private var focusedField: Field?
    @AccessibilityFocusState private var accessibilityTarget: AccessibilityTarget?

    init(email: String, request: AuthRequestState, scroll: ScrollViewProxy, onBack: @escaping () -> Void) {
        _form = State(initialValue: RegistrationForm(email: AuthRequestState.normalizedEmail(email)))
        self.request = request
        self.scroll = scroll
        self.onBack = onBack
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("Create Account")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityTarget, equals: .heading)
                .id("registration-heading")

            Text("An account is optional. Your daily card is always available without one.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Text("Email").font(.subheadline.weight(.semibold))
                AuthTextField(label: "Email", text: $form.email, isFocused: focus(.email),
                              isEnabled: !request.isWorking, contentType: .emailAddress,
                              identifier: "registration-email") {
                    focusedField = .password
                }
                .modifier(AuthFieldStyle())
                .id(Field.email)

                Text("Password").font(.subheadline.weight(.semibold))
                passwordField(label: "Password", text: $form.password,
                              visible: $form.passwordVisible, field: .password)
                Text(RegistrationForm.passwordRequirements)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("registration-requirements")

                Text("Confirm Password").font(.subheadline.weight(.semibold))
                passwordField(label: "Confirm Password", text: $form.confirmation,
                              visible: $form.confirmationVisible, field: .confirmation)
            }

            Button {
                submit()
            } label: {
                HStack {
                    if request.operation == .createAccount { ProgressView() }
                    Text(request.operation == .createAccount ? "Creating Account…" : "Create Account")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .frame(minHeight: 54)
                .background(LinearGradient(colors: [Color(red: 0.96, green: 0.72, blue: 0.40),
                                                    Color(red: 0.91, green: 0.63, blue: 0.28)],
                                           startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .tint(Color(red: 0.24, green: 0.12, blue: 0.04))
            .disabled(request.isWorking)
            .accessibilityIdentifier("registration-submit")
            .accessibilityHint("Creates your optional account. All fields are required.")

            if let message = request.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color(red: 0.65, green: 0.12, blue: 0.12))
                    .id("registration-error")
                    .accessibilityFocused($accessibilityTarget, equals: .error)
                    .task(id: request.errorPresentationID) {
                        let presentationID = request.errorPresentationID
                        accessibilityTarget = nil
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        scroll.scrollTo("registration-error", anchor: .center)
                        do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                        guard request.errorPresentationID == presentationID,
                              request.errorMessage == message else { return }
                        accessibilityTarget = .error
                    }
            }

            Button("Back to Sign In") {
                guard !request.isWorking else { return }
                focusedField = nil
                form.clearPasswords()
                request.clearFeedback()
                onBack()
            }
            .frame(minHeight: 44)
            .disabled(request.isWorking)
            .accessibilityHint("Returns to Sign In without creating an account.")

            VStack(spacing: 0) {
                Link("Privacy Policy", destination: AppLinks.privacyPolicy).frame(minHeight: 44)
                Link("Support", destination: AppLinks.support).frame(minHeight: 44)
            }
            .font(.footnote)
        }
        .tint(Color(red: 0.60, green: 0.34, blue: 0.12))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 26)
        .task {
            await Task.yield()
            scroll.scrollTo("registration-heading", anchor: .top)
            accessibilityTarget = .heading
        }
        .onChange(of: form.email) { _, _ in request.clearFeedback() }
        .onChange(of: form.password) { _, _ in request.clearFeedback() }
        .onChange(of: form.confirmation) { _, _ in request.clearFeedback() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { form.maskPasswords() }
        }
        .onChange(of: dynamicTypeSize) { _, _ in
            Task { @MainActor in
                await Task.yield()
                if let focusedField { scroll.scrollTo(focusedField, anchor: .center) }
            }
        }
        .onDisappear {
            focusedField = nil
            form.clearPasswords()
        }
    }

    private func focus(_ field: Field) -> Binding<Bool> {
        Binding(get: { focusedField == field }, set: { focused in
            if focused { focusedField = field }
            else if focusedField == field { focusedField = nil }
        })
    }

    private func passwordField(label: String, text: Binding<String>, visible: Binding<Bool>, field: Field) -> some View {
        HStack(spacing: 8) {
            AuthTextField(label: label, text: text, isFocused: focus(field),
                          isSecure: !visible.wrappedValue, isEnabled: !request.isWorking,
                          contentType: .newPassword,
                          identifier: field == .password ? "registration-password" : "registration-confirmation",
                          returnKey: field == .confirmation ? .done : .next,
                          passwordRules: RegistrationForm.passwordRules) {
                if field == .password { focusedField = .confirmation }
                else { submit() }
            }
            PasswordVisibilityButton(isVisible: visible, label: label, isEnabled: !request.isWorking)
        }
        .modifier(AuthFieldStyle())
        .id(field)
    }

    private func submit() {
        guard !request.isWorking else { return }
        focusedField = nil
        form.maskPasswords()
        let submittedForm = form
        Task {
            await request.createAccount(form: submittedForm) { email, password in
                try await router.createEmailAccount(email: email, password: password)
            }
        }
    }
}
