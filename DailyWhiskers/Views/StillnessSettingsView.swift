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
                    Toggle("Stillness Mode", isOn: $isEnabled)
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
        }
    }
}
