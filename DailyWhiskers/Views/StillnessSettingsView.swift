import SwiftUI

/// The existing Settings menu owns navigation; this sheet adds only motion controls.
struct StillnessSettingsView: View {
    @AppStorage(MotionPolicy.preferenceKey) private var isEnabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Stillness Mode", isOn: diagnosticBinding)
                        .accessibilityIdentifier("stillness-toggle")
                        .accessibilityHint("Removes decorative sparkles and ambient animation. Saved on this device.")
                } footer: {
                    Text("Enjoy calm backgrounds without decorative sparkles or ambient animation. Saved on this device, whether or not you sign in.")
                }
                Section {
                    Text(reduceMotion
                         ? "Reduce Motion is on for this device. Backgrounds stay still even when Stillness Mode is off."
                         : "Daily Whiskers also follows your device’s Reduce Motion setting.")
                        .accessibilityIdentifier("stillness-system-status")
                }
            }
            .navigationTitle("Stillness Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
#if DEBUG && CI_SMOKE_TESTING
            .onAppear { StillnessDiagnosticTrace.sheet(visible: true, value: isEnabled) }
            .onDisappear { StillnessDiagnosticTrace.sheet(visible: false, value: isEnabled) }
            .onChange(of: isEnabled) { oldValue, newValue in
                StillnessDiagnosticTrace.stateChanged(old: oldValue, new: newValue)
            }
#endif
        }
    }

    // Diagnostic-only forwarding: preserve the original transaction and one write.
    // The wrapper and observations may affect timing; a pass is not acceptance.
    private var diagnosticBinding: Binding<Bool> {
#if DEBUG && CI_SMOKE_TESTING
        if StillnessDiagnosticTrace.enabled {
            return Binding(get: { isEnabled }, set: { value, transaction in
                StillnessDiagnosticTrace.binding("binding.before", old: isEnabled, requested: value)
                $isEnabled.transaction(transaction).wrappedValue = value
                StillnessDiagnosticTrace.binding("binding.after", old: isEnabled, requested: value)
            })
        }
#endif
        return $isEnabled
    }
}
