import Testing
@testable import DailyWhiskers

@Suite("Stillness Mode")
@MainActor
struct MotionPolicyTests {
    @Test("Either preference stops decorative motion", arguments: [false, true], [false, true])
    func combinations(app: Bool, system: Bool) {
        #expect(MotionPolicy.requiresStillness(appPreference: app, systemReduceMotion: system) == (app || system))
    }

    @Test("Stillness settings remain available across account transitions")
    func accountTransitions() {
        let states: [AppRouter.AuthState] = [.loading, .signedOut, .signedIn(uid: "first"), .signedIn(uid: "second")]
        for previous in states {
            #expect(SettingsSheet.stillness.isAvailable(for: previous))
            for current in states {
                #expect(!SettingsSheet.stillness.shouldDismiss(from: previous, to: current))
            }
        }
    }
}
