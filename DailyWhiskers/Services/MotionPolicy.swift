import Foundation

enum MotionPolicy {
    // Installation-owned: never scoped to or cleared with an account.
    static let preferenceKey = "stillnessModeEnabled"

    static func requiresStillness(appPreference: Bool, systemReduceMotion: Bool) -> Bool {
        appPreference || systemReduceMotion
    }
}
