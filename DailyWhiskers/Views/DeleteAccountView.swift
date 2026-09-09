import SwiftUI

struct DeleteAccountView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var request: AuthRequestState
    @State private var password = ""
    @State private var confirmingDeletion = false
    @FocusState private var passwordFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Permanently delete your Daily Whiskers account. You will be signed out. This cannot be undone.")
                    Text("Daily cat photos and quotes are bundled with the app, not stored in your account.")
                        .foregroundStyle(.secondary)
                }
                Section("Confirm Your Identity") {
                    SecureField("Current password", text: $password)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($passwordFocused)
                        .submitLabel(.done)
                        .onSubmit { passwordFocused = false }
                        .disabled(request.isWorking)
                    Text("Forgot your password? Cancel, log out, and use Forgot password on the sign-in screen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error = request.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .accessibilityFocused($errorFocused)
                    }
                }
                Section {
                    Button(role: .destructive) {
                        passwordFocused = false
                        confirmingDeletion = true
                    } label: {
                        HStack {
                            if request.isWorking { ProgressView() }
                            Text(request.isWorking ? "Deleting Account..." : "Delete Account")
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(password.isEmpty || request.isWorking)
                }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        password = ""
                        dismiss()
                    }
                    .disabled(request.isWorking)
                }
            }
            .confirmationDialog("Permanently delete your account?", isPresented: $confirmingDeletion,
                                titleVisibility: .visible) {
                Button("Delete Permanently", role: .destructive) { deleteAccount() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This cannot be undone. Entering your password alone does not delete your account.")
            }
            .interactiveDismissDisabled(request.isWorking)
            .onChange(of: request.errorMessage) { _, error in
                errorFocused = error != nil
            }
            .onDisappear { password = "" }
        }
    }

    private func deleteAccount() {
        guard !request.isWorking, !password.isEmpty else { return }
        let submittedPassword = password
        password = ""
        UIAccessibility.post(notification: .announcement, argument: "Deleting account.")
        Task {
            await request.perform(.deleteAccount) {
                try await router.deleteAccount(password: submittedPassword)
            }
        }
    }
}
