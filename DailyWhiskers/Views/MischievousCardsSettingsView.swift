import SwiftUI

struct MischievousCardsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var enabled = false
    @State private var loaded = false
    @State private var saving = false
    private enum Retry { case load, save(Bool) }
    @State private var retry: Retry = .load
    @State private var showingError = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Mischievous Cards", isOn: Binding(get: { enabled }, set: { value in
                        Task { await save(value) }
                    }))
                    .disabled(!loaded || saving)
                    .accessibilityIdentifier("mischief-toggle")
                    .accessibilityHint("Allows rare Shadow Lord Bonus cards. Today's affirmation stays the same.")
                } footer: {
                    Text("A little feline mischief, only if you want it. Each eligible Bonus day has a 10% chance of revealing Shadow Lord, with at least 14 full days between new reveals. Becoming eligible does not guarantee a reveal.")
                }
                Section {
                    Text("Turning this off stops new mischievous cards. It won’t replace an already opened Bonus or remove your saved cards. Save a card to revisit and share it on another day.")
                    Text("Saved on this device, with or without an account. Signing out and clearing Saved Cards do not reset the history. Device backups may restore it; a fresh install without a restore starts off. Clock changes may delay new reveals.")
                }
                if let error {
                    Section {
                        Text(error).accessibilityIdentifier("mischief-error")
                        Button("Try Again") { retryLastAction() }
                    }
                }
            }
            .navigationTitle("Mischievous Cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(saving) } }
            .interactiveDismissDisabled(saving)
            .alert("Mischievous Cards Unavailable", isPresented: $showingError) {
                Button("Try Again") { retryLastAction() }
                Button("Cancel", role: .cancel) { }
            } message: { Text(error ?? "Please try again.") }
            .task { await load() }
        }
    }

    private func retryLastAction() {
        Task {
            switch retry {
            case .load: await load()
            case .save(let value): await save(value)
            }
        }
    }

    private func load() async {
        guard !saving else { return }
        do {
            enabled = try await CardRepository.shared.mischiefState().enabled
            loaded = true
            error = nil
        } catch {
            loaded = false
            retry = .load
            showingError = true
            self.error = "This preference couldn't be read. Your cards and history are kept. Please try again."
        }
    }

    private func save(_ value: Bool) async {
        guard loaded, !saving else { return }
        saving = true
        defer { saving = false }
        do {
            try await CardRepository.shared.setMischiefEnabled(value)
            enabled = value
            error = nil
        } catch {
            retry = .save(value)
            showingError = true
            self.error = "The change couldn't be saved. Your previous preference is still in effect. Please try again."
        }
    }
}
