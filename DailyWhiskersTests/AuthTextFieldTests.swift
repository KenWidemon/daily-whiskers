import SwiftUI
import Testing
import UIKit
@testable import DailyWhiskers

@Suite("Native authentication fields", .serialized)
@MainActor
struct AuthTextFieldTests {
    @Test("Returning and new passwords keep distinct AutoFill traits and private values",
          arguments: [UITextContentType.password.rawValue, UITextContentType.newPassword.rawValue])
    func passwordTraits(_ rawType: String) {
        let type = UITextContentType(rawValue: rawType)
        var input = AuthTextField(label: "Password", text: .constant(" Synthetic1 "),
                                  isFocused: .constant(false), isSecure: true,
                                  contentType: type, identifier: "test-password", onSubmit: {})
        let field = UITextField()
        input.configure(field)
        #expect(field.isSecureTextEntry)
        #expect(field.textContentType == type)
        #expect(field.passwordRules == nil)
        #expect(field.accessibilityIdentifier == "test-password")
        #expect(field.accessibilityValue == "Password entered")
        input.isSecure = false
        input.configure(field)
        #expect(!field.isSecureTextEntry)
        #expect(field.textContentType == type)
        #expect(field.accessibilityValue == "Password entered")
        #expect(field.text == " Synthetic1 ")
    }

    @Test("Visibility preserves native selection, focus, exact input and subsequent edits")
    func preservesEdit() throws {
        var draft = " Aé🐈1z "
        var focused = true
        var submissions = 0
        var input = AuthTextField(label: "Password", text: Binding(get: { draft }, set: { draft = $0 }),
                                  isFocused: Binding(get: { focused }, set: { focused = $0 }),
                                  isSecure: true, contentType: .password, identifier: "test-password",
                                  onSubmit: { submissions += 1 })
        let coordinator = input.makeCoordinator()
        let field = UITextField()
        field.delegate = coordinator
        field.addTarget(coordinator, action: #selector(AuthTextField.Coordinator.changed(_:)), for: .editingChanged)
        input.configure(field)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(field)
        window.makeKeyAndVisible()
        defer {
            field.resignFirstResponder()
            window.isHidden = true
            previousWindow?.makeKeyAndVisible()
        }
        #expect(field.becomeFirstResponder())
        // Select a composed character and a surrogate pair in the middle.
        let start = try #require(field.position(from: field.beginningOfDocument, offset: 2))
        let end = try #require(field.position(from: field.beginningOfDocument, offset: 5))
        field.selectedTextRange = field.textRange(from: start, to: end)
        for secure in [false, true, false, true] {
            input.isSecure = secure
            coordinator.parent = input
            input.configure(field)
            let selection = try #require(field.selectedTextRange)
            #expect(field.offset(from: field.beginningOfDocument, to: selection.start) == 2)
            #expect(field.offset(from: field.beginningOfDocument, to: selection.end) == 5)
            #expect(field.isFirstResponder)
            #expect(field.text?.utf8.elementsEqual(draft.utf8) == true)
            #expect(draft == " Aé🐈1z ")
        }
        field.insertText("x")
        #expect(field.text == " Ax1z ")
        #expect(draft == " Ax1z ")
        #expect(focused)
        #expect(submissions == 0)
    }

    @Test("Beginning secure editing preserves the caret or selection and subsequent input",
          arguments: [UITextContentType.password.rawValue, UITextContentType.newPassword.rawValue],
          [0..<0, 2..<2, 2..<5, 8..<8])
    func preservesSelectionOnBeginEditing(_ rawType: String, _ offsets: Range<Int>) throws {
        let original = " Aé🐈1z "
        var draft = original
        var focused = false
        var submissions = 0
        let input = AuthTextField(label: "Password", text: Binding(get: { draft }, set: { draft = $0 }),
                                  isFocused: Binding(get: { focused }, set: { focused = $0 }),
                                  isSecure: true, contentType: UITextContentType(rawValue: rawType),
                                  identifier: "test-password", onSubmit: { submissions += 1 })
        let coordinator = input.makeCoordinator()
        let field = UITextField()
        field.addTarget(coordinator, action: #selector(AuthTextField.Coordinator.changed(_:)), for: .editingChanged)
        input.configure(field)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(field)
        window.makeKeyAndVisible()
        defer {
            field.resignFirstResponder()
            window.isHidden = true
            previousWindow?.makeKeyAndVisible()
        }
        #expect(field.becomeFirstResponder())
        #expect(field.resignFirstResponder())
        #expect(field.becomeFirstResponder())
        // Supply the selection UIKit hands to the begin-editing callback.
        // Calling the delegate explicitly makes caret/range coverage deterministic.
        let start = try #require(field.position(from: field.beginningOfDocument, offset: offsets.lowerBound))
        let end = try #require(field.position(from: field.beginningOfDocument, offset: offsets.upperBound))
        field.selectedTextRange = field.textRange(from: start, to: end)
        field.delegate = coordinator
        coordinator.textFieldDidBeginEditing(field)
        let selection = try #require(field.selectedTextRange)
        #expect(field.offset(from: field.beginningOfDocument, to: selection.start) == offsets.lowerBound)
        #expect(field.offset(from: field.beginningOfDocument, to: selection.end) == offsets.upperBound)
        #expect(field.text?.utf8.elementsEqual(original.utf8) == true)
        #expect(draft.utf8.elementsEqual(original.utf8))
        #expect(field.isSecureTextEntry)
        #expect(field.isFirstResponder)
        #expect(focused)
        #expect(field.accessibilityValue == "Password entered")
        field.insertText("x")
        let expected = (original as NSString).replacingCharacters(in: NSRange(location: offsets.lowerBound,
                                                                             length: offsets.count), with: "x")
        #expect(field.text?.utf8.elementsEqual(expected.utf8) == true)
        #expect(draft.utf8.elementsEqual(expected.utf8))
        #expect(submissions == 0)
    }

    @Test("Visibility on an unfocused empty password does not focus or submit")
    func unfocusedVisibility() {
        var submissions = 0
        var input = AuthTextField(label: "Password", text: .constant(""), isFocused: .constant(false),
                                  isSecure: true, contentType: .password, identifier: "test-password",
                                  onSubmit: { submissions += 1 })
        let field = UITextField()
        for secure in [true, false, true] {
            input.isSecure = secure
            input.configure(field)
            #expect(!field.isFirstResponder)
            #expect(field.text == "")
            #expect(field.accessibilityValue == "Empty")
        }
        #expect(submissions == 0)
    }

    @Test("Email remains readable and registration alone supplies new-password rules")
    func emailAndRegistrationConfiguration() {
        let email = AuthTextField(label: "Email", text: .constant("cat@example.com"),
                                 isFocused: .constant(false), contentType: .emailAddress,
                                 identifier: "sign-in-email", onSubmit: {})
        let field = UITextField()
        email.configure(field)
        #expect(field.keyboardType == .emailAddress)
        #expect(field.accessibilityValue != "Password entered")
        let registration = AuthTextField(label: "Password", text: .constant(""), isFocused: .constant(false),
                                         isSecure: true, contentType: .newPassword, identifier: "registration-password",
                                         passwordRules: RegistrationForm.passwordRules, onSubmit: {})
        registration.configure(field)
        #expect(field.passwordRules?.passwordRulesDescriptor == RegistrationForm.passwordRules)
    }

    @Test("Explicit model clears defeat queued native reconciliation; dismantled fields cannot restore drafts")
    func clearAndDismantleWinOverPendingInput() async throws {
        var draft = "Synthetic-Original-1"
        let input = AuthTextField(label: "Password", text: Binding(get: { draft }, set: { draft = $0 }),
                                  isFocused: .constant(false), isSecure: true,
                                  contentType: .newPassword, identifier: "clear-password", onSubmit: {})
        let coordinator = input.makeCoordinator()
        let field = UITextField()
        coordinator.update(field, parent: input)
        field.text = "Synthetic-Pending-2"
        coordinator.update(field, parent: input)
        draft = ""
        coordinator.update(field, parent: input)
        try await Task.sleep(for: .milliseconds(150))
        #expect(draft.isEmpty)
        #expect(field.text == "")
        field.text = "Synthetic-Pending-3"
        coordinator.update(field, parent: input)
        AuthTextField.dismantleUIView(field, coordinator: coordinator)
        try await Task.sleep(for: .milliseconds(150))
        #expect(draft.isEmpty)
        #expect(field.text == "")
    }

    @Test("Selection and end-editing callbacks synchronize native input without duplicate model writes")
    func nativeCallbacksSynchronize() {
        var draft = ""
        var writes = 0
        let input = AuthTextField(label: "Password", text: Binding(get: { draft }, set: { draft = $0; writes += 1 }),
                                  isFocused: .constant(false), isSecure: true,
                                  contentType: .newPassword, identifier: "callback-password", onSubmit: {})
        let coordinator = input.makeCoordinator()
        let field = UITextField()
        coordinator.update(field, parent: input)
        field.text = "Synthetic-Native-1"
        coordinator.textFieldDidChangeSelection(field)
        #expect(draft == "Synthetic-Native-1")
        coordinator.changed(field)
        #expect(writes == 1)
        field.text = "Synthetic-Native-2"
        coordinator.textFieldDidEndEditing(field)
        #expect(draft == "Synthetic-Native-2")
        #expect(writes == 2)
        draft = "" // An explicit model clear wins even before updateUIView runs.
        coordinator.textFieldDidChangeSelection(field)
        #expect(draft.isEmpty)
        coordinator.update(field, parent: input)
        #expect(field.text == "")
    }

    @Test("Unrelated updates retain password-rule identity and native selection")
    func unchangedTraitsRemainStable() throws {
        let input = AuthTextField(label: "Password", text: .constant("Synthetic-Rule-1"),
                                  isFocused: .constant(false), isSecure: true,
                                  contentType: .newPassword, identifier: "rules-password",
                                  passwordRules: RegistrationForm.passwordRules, onSubmit: {})
        let coordinator = input.makeCoordinator()
        let field = UITextField()
        coordinator.update(field, parent: input)
        let rules = try #require(field.passwordRules)
        let start = try #require(field.position(from: field.beginningOfDocument, offset: 2))
        let end = try #require(field.position(from: field.beginningOfDocument, offset: 5))
        field.selectedTextRange = field.textRange(from: start, to: end)
        coordinator.update(field, parent: input)
        #expect(field.passwordRules === rules)
        let selection = try #require(field.selectedTextRange)
        #expect(field.offset(from: field.beginningOfDocument, to: selection.start) == 2)
        #expect(field.offset(from: field.beginningOfDocument, to: selection.end) == 5)
    }

    @Test("Pending native text survives Show Password with focus, range and continued editing intact")
    func pendingNativeVisibilityAndFocus() async throws {
        let host = try HostedRegistrationFields()
        defer { host.close() }
        host.model.focused = true
        try await host.settle()
        let field = try #require(host.field("pending-password"))
        #expect(field.isFirstResponder)
        let delegate = field.delegate
        field.delegate = nil
        field.text = " Aé🐈1z "
        let start = try #require(field.position(from: field.beginningOfDocument, offset: 2))
        let end = try #require(field.position(from: field.beginningOfDocument, offset: 5))
        field.selectedTextRange = field.textRange(from: start, to: end)
        field.delegate = delegate
        host.model.visible = true
        try await host.settle()
        #expect(field.isFirstResponder)
        #expect(!field.isSecureTextEntry)
        #expect(field.text == " Aé🐈1z ")
        #expect(host.model.password == " Aé🐈1z ")
        let selection = try #require(field.selectedTextRange)
        #expect(field.offset(from: field.beginningOfDocument, to: selection.start) == 2)
        #expect(field.offset(from: field.beginningOfDocument, to: selection.end) == 5)
        field.insertText("x")
        #expect(host.model.password == " Ax1z ")
        host.model.focused = false
        try await host.settle()
        #expect(!field.isFirstResponder)
        #expect(host.model.password == " Ax1z ")
    }

    @Test("A view refresh preserves and synchronizes pending native input in both registration fields")
    func pendingNativeFillSurvivesRefresh() async throws {
        let host = try HostedRegistrationFields()
        defer { host.close() }
        try await host.settle()
        let password = try #require(host.field("pending-password"))
        let confirmation = try #require(host.field("pending-confirmation"))
        let synthetic = "Synthetic-Pending-42"
        // Model a native multi-field insertion before its change callback arrives.
        // This is a bridge-ordering regression, not a real password-provider test.
        let passwordDelegate = password.delegate
        let confirmationDelegate = confirmation.delegate
        password.delegate = nil
        confirmation.delegate = nil
        password.text = synthetic
        confirmation.text = synthetic
        password.delegate = passwordDelegate
        confirmation.delegate = confirmationDelegate
        #expect(host.model.password.isEmpty)
        #expect(host.model.confirmation.isEmpty)
        host.model.revision += 1
        try await host.settle()
        #expect(password.accessibilityHint == "Refresh 1")
        #expect(password.text == synthetic)
        #expect(confirmation.text == synthetic)
        #expect(host.model.password == synthetic)
        #expect(host.model.confirmation == synthetic)
    }

}


@MainActor
private final class NativeFillModel: ObservableObject {
    @Published var password = ""
    @Published var confirmation = ""
    @Published var revision = 0
    @Published var focused = false
    @Published var visible = false
}

private struct NativeFillHarness: View {
    @ObservedObject var model: NativeFillModel
    var body: some View {
        VStack {
            AuthTextField(label: "Password", text: $model.password, isFocused: $model.focused,
                          isSecure: !model.visible, contentType: .newPassword, identifier: "pending-password",
                          accessibilityHint: "Refresh \(model.revision)",
                          passwordRules: RegistrationForm.passwordRules, onSubmit: {})
            AuthTextField(label: "Confirm Password", text: $model.confirmation, isFocused: .constant(false),
                          isSecure: true, contentType: .newPassword, identifier: "pending-confirmation",
                          accessibilityHint: "Refresh \(model.revision)",
                          passwordRules: RegistrationForm.passwordRules, onSubmit: {})
        }
    }
}

@MainActor
private final class HostedRegistrationFields {
    let model = NativeFillModel()
    let window: UIWindow
    let previousWindow: UIWindow?

    init() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previousWindow = scene.windows.first { $0.isKeyWindow }
        window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: NativeFillHarness(model: model))
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
    }

    func field(_ identifier: String) -> UITextField? {
        func search(_ view: UIView) -> UITextField? {
            if let field = view as? UITextField, field.accessibilityIdentifier == identifier { return field }
            return view.subviews.lazy.compactMap(search).first
        }
        return search(window)
    }

    func settle() async throws {
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        window.layoutIfNeeded()
    }

    func close() {
        window.endEditing(true)
        window.isHidden = true
        window.rootViewController = nil
        previousWindow?.makeKeyAndVisible()
    }
}
