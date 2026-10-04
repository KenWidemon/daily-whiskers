import SwiftUI
import UIKit

/// A stable native field keeps first responder, selection, and AutoFill intact
/// when password visibility changes. The trailing control lives in SwiftUI.
struct AuthTextField: UIViewRepresentable {
    let label: String
    @Binding var text: String
    @Binding var isFocused: Bool
    var isSecure = false
    var isEnabled = true
    let contentType: UITextContentType
    let identifier: String
    var accessibilityHint: String?
    var returnKey: UIReturnKeyType = .next
    var passwordRules: String?
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.adjustsFontForContentSizeCategory = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.update(field, parent: self)
        if isFocused && !field.isFirstResponder && isEnabled {
            DispatchQueue.main.async { [weak field, weak coordinator = context.coordinator] in
                guard let parent = coordinator?.parent, parent.isFocused, parent.isEnabled else { return }
                field?.becomeFirstResponder()
            }
        } else if !isFocused && field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    static func dismantleUIView(_ field: UITextField, coordinator: Coordinator) {
        coordinator.invalidate(field)
    }

    /// Apply traits and visibility without replacing an unreported native edit.
    func configure(_ field: UITextField, preservingNativeText nativeText: String? = nil) {
        let displayedText = nativeText ?? text
        field.font = .preferredFont(forTextStyle: .body)
        field.textColor = .label
        field.attributedPlaceholder = NSAttributedString(string: label, attributes: [.foregroundColor: UIColor(white: 0.38, alpha: 1)])
        field.accessibilityLabel = label
        field.accessibilityIdentifier = identifier
        field.accessibilityHint = accessibilityHint
        // Do not reassign unchanged AutoFill traits on unrelated renders.
        if field.textContentType != contentType { field.textContentType = contentType }
        if field.passwordRules?.passwordRulesDescriptor != passwordRules {
            field.passwordRules = passwordRules.map { UITextInputPasswordRules(descriptor: $0) }
        }
        let keyboard: UIKeyboardType = contentType == .emailAddress ? .emailAddress : .default
        if field.keyboardType != keyboard { field.keyboardType = keyboard }
        if field.returnKeyType != returnKey { field.returnKeyType = returnKey }
        field.isEnabled = isEnabled
        if !(field.text ?? "").utf8.elementsEqual(displayedText.utf8) { field.text = displayedText }
        if field.isSecureTextEntry != isSecure {
            let selection = field.selectedTextRange.map {
                (field.offset(from: field.beginningOfDocument, to: $0.start),
                 field.offset(from: field.beginningOfDocument, to: $0.end))
            }
            field.isSecureTextEntry = isSecure
            if field.isFirstResponder {
                // Reset UIKit's secure-entry replacement state through its input
                // API; assigning `text` alone can discard input on the next key.
                field.text = ""
                field.insertText(displayedText)
            }
            if let (start, end) = selection,
               let startPosition = field.position(from: field.beginningOfDocument, offset: start),
               let endPosition = field.position(from: field.beginningOfDocument, offset: end) {
                field.selectedTextRange = field.textRange(from: startPosition, to: endPosition)
            }
        }
        // Do not read a revealed password aloud when VoiceOver focuses the field.
        let isPassword = contentType == .password || contentType == .newPassword
        field.accessibilityValue = isPassword ? (displayedText.isEmpty ? "Empty" : "Password entered") : nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: max(30, uiView.intrinsicContentSize.height))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AuthTextField
        private var lastModelText: String
        private var hasConfiguredField = false
        private var isApplyingModel = false
        private var isValid = true
        private var updateRevision = 0

        init(_ parent: AuthTextField) {
            self.parent = parent
            lastModelText = parent.text
        }

        func update(_ field: UITextField, parent: AuthTextField) {
            self.parent = parent
            updateRevision += 1
            let revision = updateRevision
            let modelText = parent.text
            let modelChanged = !hasConfiguredField || !modelText.utf8.elementsEqual(lastModelText.utf8)
            hasConfiguredField = true
            // A changed model is an explicit replacement/clear. Otherwise UIKit may
            // already contain an insertion whose editingChanged callback is pending.
            if modelChanged { lastModelText = modelText }
            let displayedText = modelChanged ? modelText : (field.text ?? "")
            isApplyingModel = true
            parent.configure(field, preservingNativeText: displayedText)
            isApplyingModel = false
            guard !displayedText.utf8.elementsEqual(modelText.utf8) else { return }
            // Publishing during updateUIView would mutate SwiftUI state mid-render.
            // A newer edit, model clear, or dismantled field must win over this work.
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field, self.isValid, self.updateRevision == revision,
                      self.parent.text.utf8.elementsEqual(modelText.utf8),
                      (field.text ?? "").utf8.elementsEqual(displayedText.utf8) else { return }
                self.changed(field)
            }
        }

        @objc func changed(_ field: UITextField) {
            guard isValid, !isApplyingModel,
                  parent.text.utf8.elementsEqual(lastModelText.utf8) else { return }
            updateRevision += 1
            let text = field.text ?? ""
            lastModelText = text
            if !parent.text.utf8.elementsEqual(text.utf8) { parent.text = text }
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            // Reconcile native replacements as well as ordinary keyboard edits.
            changed(textField)
        }

        func invalidate(_ field: UITextField) {
            isValid = false
            updateRevision += 1
            field.delegate = nil
            field.removeTarget(self, action: #selector(changed(_:)), for: .editingChanged)
            field.text = ""
            lastModelText = ""
        }
        func textFieldDidBeginEditing(_ textField: UITextField) {
            if textField.isSecureTextEntry, let text = textField.text, !text.isEmpty {
                // A secure field also prepares to replace its contents when it
                // regains focus. Reinsert without moving the user's caret/range.
                let selection = textField.selectedTextRange.map {
                    (textField.offset(from: textField.beginningOfDocument, to: $0.start),
                     textField.offset(from: textField.beginningOfDocument, to: $0.end))
                }
                textField.text = ""
                textField.insertText(text)
                if let (start, end) = selection,
                   let startPosition = textField.position(from: textField.beginningOfDocument, offset: start),
                   let endPosition = textField.position(from: textField.beginningOfDocument, offset: end) {
                    textField.selectedTextRange = textField.textRange(from: startPosition, to: endPosition)
                }
            }
            if !parent.isFocused { parent.isFocused = true }
        }
        func textFieldDidEndEditing(_ textField: UITextField) {
            changed(textField)
            if parent.isFocused { parent.isFocused = false }
        }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }
}

struct AuthFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 54)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.65))
                .shadow(color: .black.opacity(0.03), radius: 8, y: 3))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.black.opacity(0.06), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.025), radius: 8, y: 3)
    }
}

/// Shared action/state wording and touch target for both account forms.
struct PasswordVisibilityButton: View {
    @Binding var isVisible: Bool
    var label = "Password"
    var isEnabled = true

    var body: some View {
        Button {
            isVisible.toggle()
        } label: {
            Image(systemName: isVisible ? "eye.slash" : "eye")
                .frame(minWidth: 44, minHeight: 44)
        }
        .tint(Color(red: 0.60, green: 0.34, blue: 0.12))
        .accessibilityLabel("\(isVisible ? "Hide" : "Show") \(label)")
        .accessibilityValue(isVisible ? "Visible" : "Hidden")
        .disabled(!isEnabled)
    }
}
