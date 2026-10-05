import SwiftUI
import Testing
import UIKit
@testable import DailyWhiskers

@Suite("Native authentication fields", .serialized)
@MainActor
struct AuthTextFieldTests {
    @Test("Repeated registration mounts discard old native fields and accept new native edits")
    func repeatedRegistrationMounts() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let probe = RegistrationNavigationProbe()
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: RegistrationNavigationHarness(probe: probe))
        window.makeKeyAndVisible()
        defer {
            window.endEditing(true)
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        func settle() async throws {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            window.layoutIfNeeded()
        }
        func field(_ identifier: String, in view: UIView) -> UITextField? {
            if let input = view as? UITextField, input.accessibilityIdentifier == identifier { return input }
            return view.subviews.lazy.compactMap { field(identifier, in: $0) }.first
        }
        // Keep the old objects alive so pointer reuse cannot masquerade as reuse
        // of a field. This harness tests removal/recreation of the real form;
        // the UI test exercises the actual AuthView Back/Close button actions.
        var retired: [UITextField] = []
        try await settle()
        for _ in 0..<3 {
            probe.showingRegistration = true
            try await settle()
            let email = try #require(field("registration-email", in: window))
            let password = try #require(field("registration-password", in: window))
            let confirmation = try #require(field("registration-confirmation", in: window))
            for input in [email, password, confirmation] {
                #expect(!retired.contains { $0 === input })
                #expect(input.text?.isEmpty != false)
                #expect(!input.isFirstResponder)
            }
            #expect(email.textContentType == .username)
            #expect(email.keyboardType == .emailAddress)
            #expect(email.becomeFirstResponder())
            email.insertText("repeat@example.invalid")
            #expect(password.becomeFirstResponder())
            try await settle()
            // Synthetic native replacement exercises the bridge, not the
            // system password provider or its strong-password panel.
            for input in [password, confirmation] {
                #expect(input.textContentType == .newPassword)
                #expect(input.passwordRules?.passwordRulesDescriptor == RegistrationForm.passwordRules)
                #expect(input.isSecureTextEntry)
                input.text = "Synthetic-Repeat-1"
                input.delegate?.textFieldDidChangeSelection?(input)
            }
            try await settle()
            #expect(confirmation.becomeFirstResponder())
            try await settle()
            #expect(password.becomeFirstResponder())
            try await settle()
            #expect(field("registration-password", in: window) === password)
            #expect(field("registration-confirmation", in: window) === confirmation)
            #expect(password.text == "Synthetic-Repeat-1")
            #expect(confirmation.text == "Synthetic-Repeat-1")
            let oldCoordinator = try #require(password.delegate as? AuthTextField.Coordinator)
            probe.showingRegistration = false
            try await settle()
            #expect(field("registration-password", in: window) == nil)
            for input in [email, password, confirmation] {
                #expect(input.delegate == nil)
                #expect(input.text == "")
                #expect(!input.isFirstResponder)
            }
            // An already queued callback from a dismantled form must be inert.
            password.text = "Synthetic-Late-2"
            oldCoordinator.changed(password)
            retired += [email, password, confirmation]
        }
    }

    @Test("The real registration form tags its account identifier and both new-password fields")
    func registrationFormTraits() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: RegistrationTraitHarness())
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        func field(_ identifier: String, in view: UIView) -> UITextField? {
            if let input = view as? UITextField, input.accessibilityIdentifier == identifier { return input }
            return view.subviews.lazy.compactMap { field(identifier, in: $0) }.first
        }
        let email = try #require(field("registration-email", in: window))
        #expect(email.textContentType == .username)
        #expect(email.keyboardType == .emailAddress)
        #expect(!email.isSecureTextEntry)
        for identifier in ["registration-password", "registration-confirmation"] {
            let password = try #require(field(identifier, in: window))
            #expect(password.textContentType == .newPassword)
            #expect(password.passwordRules?.passwordRulesDescriptor == RegistrationForm.passwordRules)
            #expect(password.isSecureTextEntry)
        }
    }

    @Test("Email account identifiers use username semantics with an email keyboard")
    func usernameWithEmailKeyboard() {
        let input = AuthTextField(label: "Email", text: .constant(""), isFocused: .constant(false),
                                  contentType: .username, keyboardType: .emailAddress,
                                  identifier: "registration-email", onSubmit: {})
        let field = UITextField()
        input.configure(field)
        let originalContentType = field.textContentType
        input.configure(field)
        #expect(field.textContentType == .username)
        #expect(field.textContentType == originalContentType)
        #expect(field.keyboardType == .emailAddress)
        #expect(!field.isSecureTextEntry)
        #expect(field.passwordRules == nil)
    }

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

    @Test("Production State form bindings retain native two-field replacement with delegates active")
    func stateFormRetainsNativeReplacement() async throws {
        let host = try HostedStateRegistrationFields()
        defer { host.close() }
        try await host.settle()
        let password = try #require(host.field("state-password"))
        let confirmation = try #require(host.field("state-confirmation"))
        let synthetic = "Synthetic-State-42"
        // Exercise live delegates and projected members of one @State value.
        // These native operations still do not simulate a password provider.
        password.text = synthetic
        confirmation.text = synthetic
        password.sendActions(for: .editingChanged)
        confirmation.sendActions(for: .editingChanged)
        host.probe.revision += 1
        try await host.settle()
        let nativeValuesMatch = password.text == synthetic && confirmation.text == synthetic
        let modelValuesMatch = host.probe.form.password == synthetic && host.probe.form.confirmation == synthetic
        #expect(nativeValuesMatch)
        #expect(modelValuesMatch)

        host.probe.clearRequest += 1
        try await host.settle()
        let nativeDraftDiscarded = password.text == "" && confirmation.text == ""
        let modelDraftDiscarded = host.probe.form.password.isEmpty && host.probe.form.confirmation.isEmpty
        #expect(nativeDraftDiscarded)
        #expect(modelDraftDiscarded)
    }

    @Test("Production State form retains unreported native replacements across a refresh")
    func stateFormRetainsPendingNativeReplacement() async throws {
        let host = try HostedStateRegistrationFields()
        defer { host.close() }
        try await host.settle()
        let password = try #require(host.field("state-password"))
        let confirmation = try #require(host.field("state-confirmation"))
        let synthetic = "Synthetic-State-Pending-42"
        password.text = synthetic
        confirmation.text = synthetic
        host.probe.revision += 1
        try await host.settle()
        let nativeValuesMatch = password.text == synthetic && confirmation.text == synthetic
        let modelValuesMatch = host.probe.form.password == synthetic && host.probe.form.confirmation == synthetic
        #expect(nativeValuesMatch)
        #expect(modelValuesMatch)
    }

    @Test("Secure native refocus does not publish an intermediate cleared model")
    func secureRefocusDoesNotPublishTransientClear() async throws {
        var draft = "Synthetic-Refocus-42"
        var focused = false
        var transientClearPublished = false
        let input = AuthTextField(label: "Password", text: Binding(get: { draft }, set: {
            if $0.isEmpty { transientClearPublished = true }
            draft = $0
        }), isFocused: Binding(get: { focused }, set: { focused = $0 }),
        isSecure: true, contentType: .newPassword, identifier: "refocus-probe", onSubmit: {})
        let coordinator = input.makeCoordinator()
        let field = UITextField()
        field.delegate = coordinator
        field.addTarget(coordinator, action: #selector(AuthTextField.Coordinator.changed(_:)), for: .editingChanged)
        coordinator.update(field, parent: input)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(field)
        window.makeKeyAndVisible()
        defer {
            field.resignFirstResponder()
            window.isHidden = true
            previous?.makeKeyAndVisible()
        }
        #expect(field.becomeFirstResponder())
        try await Task.sleep(for: .milliseconds(150))
        #expect(field.resignFirstResponder())
        #expect(field.becomeFirstResponder())
        try await Task.sleep(for: .milliseconds(150))
        let finalValuePreserved = draft == "Synthetic-Refocus-42" && field.text == draft
        #expect(finalValuePreserved)
        #expect(!transientClearPublished)
    }

}

@MainActor
private final class StateRegistrationProbe: ObservableObject {
    @Published var revision = 0
    @Published var clearRequest = 0
    var form = RegistrationForm()
}

private struct StateRegistrationHarness: View {
    @ObservedObject var probe: StateRegistrationProbe
    @State private var form = RegistrationForm()
    @State private var focusedField: Int?

    private func focus(_ field: Int) -> Binding<Bool> {
        Binding(get: { focusedField == field }, set: { focused in
            if focused { focusedField = field }
            else if focusedField == field { focusedField = nil }
        })
    }

    var body: some View {
        VStack {
            AuthTextField(label: "Password", text: $form.password, isFocused: focus(1),
                          isSecure: !form.passwordVisible, contentType: .newPassword,
                          identifier: "state-password", accessibilityHint: "Refresh \(probe.revision)",
                          passwordRules: RegistrationForm.passwordRules, onSubmit: {})
            AuthTextField(label: "Confirm Password", text: $form.confirmation, isFocused: focus(2),
                          isSecure: !form.confirmationVisible, contentType: .newPassword,
                          identifier: "state-confirmation", accessibilityHint: "Refresh \(probe.revision)",
                          passwordRules: RegistrationForm.passwordRules, onSubmit: {})
        }
        .onChange(of: form) { _, updated in probe.form = updated }
        .onChange(of: probe.clearRequest) { _, _ in
            focusedField = nil
            form.clearPasswords()
        }
    }
}

@MainActor
private final class HostedStateRegistrationFields {
    let probe = StateRegistrationProbe()
    let window: UIWindow
    let previousWindow: UIWindow?

    init() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previousWindow = scene.windows.first { $0.isKeyWindow }
        window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: StateRegistrationHarness(probe: probe))
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

private struct RegistrationTraitHarness: View {
    @StateObject private var request = AuthRequestState()
    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                CreateAccountView(email: "", request: request, scroll: scroll, onBack: {})
            }
        }
    }
}

@MainActor
private final class RegistrationNavigationProbe: ObservableObject {
    @Published var showingRegistration = false
}

private struct RegistrationNavigationHarness: View {
    @ObservedObject var probe: RegistrationNavigationProbe
    @StateObject private var request = AuthRequestState()

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollViewReader { scroll in
                    ScrollView {
                        Group {
                            if probe.showingRegistration {
                                CreateAccountView(email: "", request: request, scroll: scroll) {
                                    probe.showingRegistration = false
                                }
                            } else {
                                Text("Sign In")
                            }
                        }
                        .frame(maxWidth: 520)
                        .padding(.vertical, 28)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geometry.size.height)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
    }
}
