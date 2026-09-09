import FirebaseAuth
import Foundation
import Testing
@testable import DailyWhiskers

@Suite("Account deletion")
@MainActor
struct AccountDeletionTests {
    @Test("Empty password does not contact auth or delete")
    func emptyPassword() async {
        var calls = 0
        let state = AuthRequestState()
        await state.perform(.deleteAccount) {
            try await AccountDeletion.perform(password: "") { _ in calls += 1 } delete: { calls += 1 }
        }
        #expect(calls == 0)
        #expect(state.errorMessage == "Enter your current password to delete your account.")
        #expect(!state.isWorking)
    }

    @Test("Reauth succeeds before delete and passwords are not normalized")
    func orderedDeletion() async throws {
        var events: [String] = []
        try await AccountDeletion.perform(password: " test password ") { password in
            #expect(password == " test password ")
            events.append("reauthenticate")
        } delete: {
            events.append("delete")
        }
        #expect(events == ["reauthenticate", "delete"])
    }

    @Test("Failed reauthentication prevents deletion")
    func failedReauthentication() async {
        var deleted = false
        let state = AuthRequestState()
        await state.perform(.deleteAccount) {
            try await AccountDeletion.perform(password: "incorrect") { _ in
                throw NSError(domain: AuthErrorDomain, code: AuthErrorCode.wrongPassword.rawValue)
            } delete: { deleted = true }
        }
        #expect(!deleted)
        #expect(state.errorMessage == "Couldn't verify your password. Enter your current password and try again.")
        #expect(!state.isWorking)
    }

    @Test("Deletion failure permits a fresh reauthentication and retry")
    func retry() async {
        let state = AuthRequestState()
        var reauthCalls = 0
        var deleteCalls = 0
        for attempt in 0..<2 {
            await state.perform(.deleteAccount) {
                try await AccountDeletion.perform(password: "test password") { _ in
                    reauthCalls += 1
                } delete: {
                    deleteCalls += 1
                    if attempt == 0 {
                        throw NSError(domain: AuthErrorDomain, code: AuthErrorCode.networkError.rawValue)
                    }
                }
            }
            #expect(!state.isWorking)
            if attempt == 0 { #expect(state.errorMessage != nil) }
        }
        #expect(reauthCalls == 2)
        #expect(deleteCalls == 2)
        #expect(state.errorMessage == nil)
    }

    @Test("Cancellation after reauth never issues delete")
    func cancelledReauthentication() async {
        var resume: CheckedContinuation<Void, Never>?
        var deleted = false
        let state = AuthRequestState()
        var task: Task<Void, Never>?
        await withCheckedContinuation { started in
            task = Task {
                await state.perform(.deleteAccount) {
                    try await AccountDeletion.perform(password: "test password") { _ in
                        await withCheckedContinuation { continuation in
                            resume = continuation
                            started.resume()
                        }
                    } delete: { deleted = true }
                }
            }
        }
        task?.cancel()
        resume?.resume()
        await task?.value
        #expect(!deleted)
        #expect(!state.isWorking)
        #expect(state.errorMessage == nil)
    }

    @Test("Account session changes have actionable feedback")
    func sessionChanged() {
        #expect(AuthErrorMapper.message(for: AccountDeletionError.sessionChanged, context: .accountDeletion)
                == "Your session changed. Sign in again before deleting your account.")
    }

    @Test("Unknown deletion failures do not expose backend descriptions")
    func unknownError() {
        let error = NSError(domain: "PrivateBackend", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "sensitive backend detail"])
        #expect(AuthErrorMapper.message(for: error, context: .accountDeletion)
                == "Couldn't delete your account. Please try again.")
    }

    @Test("App privacy manifest is bundled with account data declarations")
    func privacyManifest() throws {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        let manifest = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        let types = try #require(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        for name in ["NSPrivacyCollectedDataTypeEmailAddress", "NSPrivacyCollectedDataTypeUserID"] {
            let declaration = try #require(types.first { $0["NSPrivacyCollectedDataType"] as? String == name })
            #expect(declaration["NSPrivacyCollectedDataTypeLinked"] as? Bool == true)
            #expect(declaration["NSPrivacyCollectedDataTypeTracking"] as? Bool == false)
            #expect(declaration["NSPrivacyCollectedDataTypePurposes"] as? [String]
                    == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])
        }
    }
}
